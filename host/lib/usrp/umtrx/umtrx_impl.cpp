// Copyright 2012-2013 Fairwaves LLC
// Copyright 2010-2011 Ettus Research LLC
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
#include "umtrx_impl.hpp"
#include "lms_regs.hpp"
#include "umtrx_regs.hpp"
#include "../usrp2/fw_common.h"
#include "../../transport/super_recv_packet_handler.hpp"
#include "../../transport/super_send_packet_handler.hpp"
#include "apply_corrections.hpp"
#include <uhd/utils/log.hpp>
#include <uhd/utils/msg.hpp>
#include <uhd/exception.hpp>
#include <uhd/transport/if_addrs.hpp>
#include <uhd/transport/udp_zero_copy.hpp>
#include <uhd/types/ranges.hpp>
#include <uhd/exception.hpp>
#include <uhd/utils/static.hpp>
#include <uhd/utils/byteswap.hpp>
#include <uhd/utils/safe_call.hpp>
#include <uhd/utils/tasks.hpp>
#include <boost/format.hpp>
#include <boost/foreach.hpp>
#include <boost/lexical_cast.hpp>
#include <boost/bind.hpp>
#include <boost/make_shared.hpp>
#include <boost/assign/list_of.hpp>
#include <boost/asio/ip/address_v4.hpp>
#include <boost/asio.hpp> //used for htonl and ntohl
#include "validate_subdev_spec.hpp"
#include <uhd/usrp/dboard_iface.hpp>

static int verbosity = 0;

using namespace uhd;
using namespace uhd::usrp;
using namespace uhd::transport;
namespace asio = boost::asio;

/***********************************************************************
 * Make
 **********************************************************************/
static device::sptr umtrx_make(const device_addr_t &device_addr){
    return device::sptr(new umtrx_impl(device_addr));
}

static device_addrs_t umtrx_find(const device_addr_t &hint_) {
    return usrp2_find_generic(hint_, (char *)"umtrx", UMTRX_CTRL_ID_REQUEST, UMTRX_CTRL_ID_RESPONSE);
}

UHD_STATIC_BLOCK(register_umtrx_device){
    device::register_device(&umtrx_find, &umtrx_make);
}

/***********************************************************************
 * Helpers
 **********************************************************************/

static zero_copy_if::sptr make_xport(
    const std::string &addr,
    const std::string &port,
    const device_addr_t &hints,
    const std::string &filter
){

    //only copy hints that contain the filter word
    device_addr_t filtered_hints;
    BOOST_FOREACH(const std::string &key, hints.keys()){
        if (key.find(filter) == std::string::npos) continue;
        filtered_hints[key] = hints[key];
    }

    //make the transport object with the filtered hints
    zero_copy_if::sptr xport = udp_zero_copy::make(addr, port, filtered_hints);

    //Send a small data packet so the umtrx knows the udp source port.
    //This setup must happen before further initialization occurs
    //or the async update packets will cause ICMP destination unreachable.
    static const boost::uint32_t data[2] = {
        uhd::htonx(boost::uint32_t(0 /* don't care seq num */)),
        uhd::htonx(boost::uint32_t(USRP2_INVALID_VRT_HEADER))
    };
    transport::managed_send_buffer::sptr send_buff = xport->get_send_buff();
    std::memcpy(send_buff->cast<void*>(), &data, sizeof(data));
    send_buff->commit(sizeof(data));

    return xport;
}

/***********************************************************************
 * Structors
 **********************************************************************/
umtrx_impl::umtrx_impl(const device_addr_t &_device_addr)
    : _mcr(26e6/2) // sample rate = ref_clk / 2
{
    UHD_MSG(status) << "Opening a UmTRX device..." << std::endl;
    device_addr_t device_addr = _device_addr;
    //setup the dsp transport hints (default to a large recv buff)
    if (not device_addr.has_key("recv_buff_size")){
        #if defined(UHD_PLATFORM_MACOS) || defined(UHD_PLATFORM_BSD)
            //limit buffer resize on macos or it will error
            device_addr["recv_buff_size"] = "1e6";
        #elif defined(UHD_PLATFORM_LINUX) || defined(UHD_PLATFORM_WIN32)
            //set to half-a-second of buffering at max rate
            device_addr["recv_buff_size"] = "50e6";
        #endif
    }
    if (not device_addr.has_key("send_buff_size")){
        //The buffer should be the size of the SRAM on the device,
        //because we will never commit more than the SRAM can hold.
        device_addr["send_buff_size"] = boost::lexical_cast<std::string>(UMTRX_SRAM_BYTES);
    }

    device_addrs_t device_args = separate_device_addr(device_addr);

    //extract the user's requested MTU size or default
    mtu_result_t user_mtu;
    user_mtu.recv_mtu = size_t(device_addr.cast<double>("recv_frame_size", udp_simple::mtu));
    user_mtu.send_mtu = size_t(device_addr.cast<double>("send_frame_size", udp_simple::mtu));

    try{
        //calculate the minimum send and recv mtu of all devices
        mtu_result_t mtu = determine_mtu(device_args[0]["addr"], user_mtu);
        for (size_t i = 1; i < device_args.size(); i++){
            mtu_result_t mtu_i = determine_mtu(device_args[i]["addr"], user_mtu);
            mtu.recv_mtu = std::min(mtu.recv_mtu, mtu_i.recv_mtu);
            mtu.send_mtu = std::min(mtu.send_mtu, mtu_i.send_mtu);
        }

        device_addr["recv_frame_size"] = boost::lexical_cast<std::string>(mtu.recv_mtu);
        device_addr["send_frame_size"] = boost::lexical_cast<std::string>(mtu.send_mtu);

        UHD_MSG(status) << boost::format("Current recv frame size: %d bytes") % mtu.recv_mtu << std::endl;
        UHD_MSG(status) << boost::format("Current send frame size: %d bytes") % mtu.send_mtu << std::endl;
    }
    catch(const uhd::not_implemented_error &){
        //just ignore this error, makes older fw work...
    }

    device_args = separate_device_addr(device_addr); //update args for new frame sizes

    ////////////////////////////////////////////////////////////////////
    // create controller objects and initialize the properties tree
    ////////////////////////////////////////////////////////////////////
    _tree = property_tree::make();
    _tree->create<std::string>("/name").set("UmTRX Device");

    for (size_t mbi = 0; mbi < device_args.size(); mbi++){
        const device_addr_t device_args_i = device_args[mbi];
        const std::string mb = boost::lexical_cast<std::string>(mbi);
        const std::string addr = device_args_i["addr"];
        const fs_path mb_path = "/mboards/" + mb;

        ////////////////////////////////////////////////////////////////
        // create the iface that controls i2c, spi, uart, and wb
        ////////////////////////////////////////////////////////////////
        _mbc[mb].iface = usrp2_iface::make(udp_simple::make_connected(
            addr, BOOST_STRINGIZE(USRP2_UDP_CTRL_PORT)
        ));
        _tree->create<std::string>(mb_path / "name").set(_mbc[mb].iface->get_cname());
        _tree->create<std::string>(mb_path / "fw_version").set(_mbc[mb].iface->get_fw_version_string());

        //check the fpga compatibility number
        const boost::uint32_t fpga_compat_num = _mbc[mb].iface->peek32(U2_REG_COMPAT_NUM_RB);
        boost::uint16_t fpga_major = fpga_compat_num >> 16, fpga_minor = fpga_compat_num & 0xffff;
        if (fpga_major == 0){ //old version scheme
            fpga_major = fpga_minor;
            fpga_minor = 0;
        }
        if (fpga_major != USRP2_FPGA_COMPAT_NUM){
            throw uhd::runtime_error(str(boost::format(
                "\nPlease update the firmware and FPGA images for your device.\n"
                "See the application notes for UmTRX for instructions.\n"
                "Expected FPGA compatibility number %d, but got %d:\n"
                "The FPGA build is not compatible with the host code build."
            ) % int(USRP2_FPGA_COMPAT_NUM) % fpga_major));
        }
        _tree->create<std::string>(mb_path / "fpga_version").set(str(boost::format("%u.%u") % fpga_major % fpga_minor));

        //lock the device/motherboard to this process
        _mbc[mb].iface->lock_device(true);

        ////////////////////////////////////////////////////////////////
        // construct transports for RX and TX DSPs
        ////////////////////////////////////////////////////////////////
        UHD_LOG << "Making transport for RX DSP0..." << std::endl;
        _mbc[mb].rx_dsp_xports.push_back(make_xport(
            addr, BOOST_STRINGIZE(USRP2_UDP_RX_DSP0_PORT), device_args_i, "recv"
        ));
        UHD_LOG << "Making transport for RX DSP1..." << std::endl;
        _mbc[mb].rx_dsp_xports.push_back(make_xport(
            addr, BOOST_STRINGIZE(USRP2_UDP_RX_DSP1_PORT), device_args_i, "recv"
        ));
        UHD_LOG << "Making transport for TX DSP0..." << std::endl;
        _mbc[mb].tx_dsp_xports.push_back(make_xport(
            addr, BOOST_STRINGIZE(USRP2_UDP_TX_DSP0_PORT), device_args_i, "send"
        ));
        UHD_LOG << "Making transport for TX DSP1..." << std::endl;
        _mbc[mb].tx_dsp_xports.push_back(make_xport(
            addr, BOOST_STRINGIZE(USRP2_UDP_TX_DSP1_PORT), device_args_i, "send"
        ));
        //set the filter on the router to take dsp data from these ports
        _mbc[mb].iface->poke32(U2_REG_ROUTER_CTRL_PORTS, ((uint32_t)USRP2_UDP_TX_DSP1_PORT)<<16 | USRP2_UDP_TX_DSP0_PORT);

        ////////////////////////////////////////////////////////////////
        // setup the mboard eeprom
        ////////////////////////////////////////////////////////////////
        _tree->create<mboard_eeprom_t>(mb_path / "eeprom")
            .set(_mbc[mb].iface->mb_eeprom)
            .subscribe(boost::bind(&umtrx_impl::set_mb_eeprom, this, mb, _1));

        ////////////////////////////////////////////////////////////////
        // create clock control objects
        ////////////////////////////////////////////////////////////////
//        _mbc[mb].clock = umtrx_clock_ctrl::make(_mbc[mb].iface);
        _tree->create<double>(mb_path / "tick_rate")
            .publish(boost::bind(&umtrx_impl::get_master_clock_rate, this))
            .subscribe(boost::bind(&umtrx_impl::update_tick_rate, this, _1));

        ////////////////////////////////////////////////////////////////
        // reset LMS chips
        ////////////////////////////////////////////////////////////////

        {
            const boost::uint32_t clock_ctrl = _mbc[mb].iface->peek32(U2_REG_MISC_CTRL_CLOCK);
            _mbc[mb].iface->poke32(U2_REG_MISC_CTRL_CLOCK, clock_ctrl & ~(LMS1_RESET|LMS2_RESET));
            _mbc[mb].iface->poke32(U2_REG_MISC_CTRL_CLOCK, clock_ctrl |  (LMS1_RESET|LMS2_RESET));
        }

        ////////////////////////////////////////////////////////////////
        // create (fake) daughterboard entries
        ////////////////////////////////////////////////////////////////
        _mbc[mb].dbc["A"];
        _mbc[mb].dbc["B"];

        ////////////////////////////////////////////////////////////////
        // create codec control objects
        ////////////////////////////////////////////////////////////////
        BOOST_FOREACH(const std::string &db, _mbc[mb].dbc.keys()){
            const fs_path rx_codec_path = mb_path / "rx_codecs" / db;
            const fs_path tx_codec_path = mb_path / "tx_codecs" / db;
            _tree->create<int>(rx_codec_path / "gains"); //phony property so this dir exists
            _tree->create<int>(tx_codec_path / "gains"); //phony property so this dir exists
            // TODO: Implement "gains" as well
            _tree->create<std::string>(tx_codec_path / "name").set("LMS_TX");
            _tree->create<std::string>(rx_codec_path / "name").set("LMS_RX");
        }

        ////////////////////////////////////////////////////////////////
        // create gpsdo control objects
        ////////////////////////////////////////////////////////////////
        if (_mbc[mb].iface->mb_eeprom["gpsdo"] == "internal"){
            _mbc[mb].gps = gps_ctrl::make(udp_simple::make_uart(udp_simple::make_connected(
                addr, BOOST_STRINGIZE(umtrx_UDP_UART_GPS_PORT)
            )));
            if(_mbc[mb].gps->gps_detected()) {
                BOOST_FOREACH(const std::string &name, _mbc[mb].gps->get_sensors()){
                    _tree->create<sensor_value_t>(mb_path / "sensors" / name)
                        .publish(boost::bind(&gps_ctrl::get_sensor, _mbc[mb].gps, name));
                }
            }
        }

        ////////////////////////////////////////////////////////////////
        // and do the misc mboard sensors
        ////////////////////////////////////////////////////////////////
//        _tree->create<sensor_value_t>(mb_path / "sensors/mimo_locked")
//            .publish(boost::bind(&umtrx_impl::get_mimo_locked, this, mb));
        _tree->create<sensor_value_t>(mb_path / "sensors/ref_locked");
//            .publish(boost::bind(&umtrx_impl::get_ref_locked, this, mb));

        ////////////////////////////////////////////////////////////////
        // create frontend control objects
        ////////////////////////////////////////////////////////////////
        _mbc[mb].rx_fes.push_back(rx_frontend_core_200::make(
            _mbc[mb].iface, U2_REG_SR_ADDR(SR_RX_FRONT0)
        ));
        _mbc[mb].tx_fes.push_back(tx_frontend_core_200::make(
            _mbc[mb].iface, U2_REG_SR_ADDR(SR_TX_FRONT0)
        ));
        _mbc[mb].rx_fes.push_back(rx_frontend_core_200::make(
            _mbc[mb].iface, U2_REG_SR_ADDR(SR_RX_FRONT1)
        ));
        _mbc[mb].tx_fes.push_back(tx_frontend_core_200::make(
            _mbc[mb].iface, U2_REG_SR_ADDR(SR_TX_FRONT1)
        ));

        _tree->create<subdev_spec_t>(mb_path / "rx_subdev_spec")
            .subscribe(boost::bind(&umtrx_impl::update_rx_subdev_spec, this, mb, _1));
        _tree->create<subdev_spec_t>(mb_path / "tx_subdev_spec")
            .subscribe(boost::bind(&umtrx_impl::update_tx_subdev_spec, this, mb, _1));

        BOOST_FOREACH(const std::string &db, _mbc[mb].dbc.keys()){
            const fs_path rx_fe_path = mb_path / "rx_frontends" / db;
            const fs_path tx_fe_path = mb_path / "tx_frontends" / db;
            const rx_frontend_core_200::sptr rx_fe = (db=="A")?_mbc[mb].rx_fes[0]:_mbc[mb].rx_fes[1];
            const tx_frontend_core_200::sptr tx_fe = (db=="A")?_mbc[mb].tx_fes[0]:_mbc[mb].tx_fes[1];

            _tree->create<std::complex<double> >(rx_fe_path / "dc_offset" / "value")
                .coerce(boost::bind(&rx_frontend_core_200::set_dc_offset, rx_fe, _1))
                .set(std::complex<double>(0.0, 0.0));
            _tree->create<bool>(rx_fe_path / "dc_offset" / "enable")
                .subscribe(boost::bind(&rx_frontend_core_200::set_dc_offset_auto, rx_fe, _1))
                .set(true);
            _tree->create<std::complex<double> >(rx_fe_path / "iq_balance" / "value")
                .subscribe(boost::bind(&rx_frontend_core_200::set_iq_balance, rx_fe, _1))
                .set(std::polar<double>(1.0, 0.0));
            _tree->create<std::complex<double> >(tx_fe_path / "dc_offset" / "value")
                .coerce(boost::bind(&tx_frontend_core_200::set_dc_offset, tx_fe, _1))
                .set(std::complex<double>(0.0, 0.0));
            _tree->create<std::complex<double> >(tx_fe_path / "iq_balance" / "value")
                .subscribe(boost::bind(&tx_frontend_core_200::set_iq_balance, tx_fe, _1))
                .set(std::polar<double>(1.0, 0.0));
        }

        ////////////////////////////////////////////////////////////////
        // create rx dsp control objects
        ////////////////////////////////////////////////////////////////
        _mbc[mb].rx_dsps.push_back(rx_dsp_core_200::make(
            _mbc[mb].iface, U2_REG_SR_ADDR(SR_RX_DSP0), U2_REG_SR_ADDR(SR_RX_CTRL0), USRP2_RX_SID_BASE + 0, true
        ));
        _mbc[mb].rx_dsps.push_back(rx_dsp_core_200::make(
            _mbc[mb].iface, U2_REG_SR_ADDR(SR_RX_DSP1), U2_REG_SR_ADDR(SR_RX_CTRL1), USRP2_RX_SID_BASE + 1, true
        ));
        for (size_t dspno = 0; dspno < _mbc[mb].rx_dsps.size(); dspno++){
            _mbc[mb].rx_dsps[dspno]->set_link_rate(USRP2_LINK_RATE_BPS);
            _tree->access<double>(mb_path / "tick_rate")
                .subscribe(boost::bind(&rx_dsp_core_200::set_tick_rate, _mbc[mb].rx_dsps[dspno], _1));
            fs_path rx_dsp_path = mb_path / str(boost::format("rx_dsps/%u") % dspno);
            _tree->create<meta_range_t>(rx_dsp_path / "rate/range")
                .publish(boost::bind(&rx_dsp_core_200::get_host_rates, _mbc[mb].rx_dsps[dspno]));
            _tree->create<double>(rx_dsp_path / "rate/value")
                .set(1e6) //some default
                .coerce(boost::bind(&rx_dsp_core_200::set_host_rate, _mbc[mb].rx_dsps[dspno], _1))
                .subscribe(boost::bind(&umtrx_impl::update_rx_samp_rate, this, mb, dspno, _1));
            _tree->create<double>(rx_dsp_path / "freq/value")
                .coerce(boost::bind(&rx_dsp_core_200::set_freq, _mbc[mb].rx_dsps[dspno], _1));
            _tree->create<meta_range_t>(rx_dsp_path / "freq/range")
                .publish(boost::bind(&rx_dsp_core_200::get_freq_range, _mbc[mb].rx_dsps[dspno]));
            _tree->create<stream_cmd_t>(rx_dsp_path / "stream_cmd")
                .subscribe(boost::bind(&rx_dsp_core_200::issue_stream_command, _mbc[mb].rx_dsps[dspno], _1));
        }

        ////////////////////////////////////////////////////////////////
        // create tx dsp control objects
        ////////////////////////////////////////////////////////////////
        _mbc[mb].tx_dsps.push_back(tx_dsp_core_200::make(
            _mbc[mb].iface, U2_REG_SR_ADDR(SR_TX_DSP0), U2_REG_SR_ADDR(SR_TX_CTRL0), USRP2_TX_ASYNC_SID_BASE+0
        ));
        _mbc[mb].tx_dsps.push_back(tx_dsp_core_200::make(
            _mbc[mb].iface, U2_REG_SR_ADDR(SR_TX_DSP1), U2_REG_SR_ADDR(SR_TX_CTRL1), USRP2_TX_ASYNC_SID_BASE+1
        ));
        for (size_t dspno = 0; dspno < _mbc[mb].tx_dsps.size(); dspno++){
            _mbc[mb].tx_dsps[dspno]->set_link_rate(USRP2_LINK_RATE_BPS);
            _tree->access<double>(mb_path / "tick_rate")
                .subscribe(boost::bind(&tx_dsp_core_200::set_tick_rate, _mbc[mb].tx_dsps[dspno], _1));
            fs_path tx_dsp_path = mb_path / str(boost::format("tx_dsps/%u") % dspno);
            _tree->create<meta_range_t>(tx_dsp_path / "rate/range")
                .publish(boost::bind(&tx_dsp_core_200::get_host_rates, _mbc[mb].tx_dsps[dspno]));
            _tree->create<double>(tx_dsp_path / "rate/value")
                .set(1e6) //some default
                .coerce(boost::bind(&tx_dsp_core_200::set_host_rate, _mbc[mb].tx_dsps[dspno], _1))
                .subscribe(boost::bind(&umtrx_impl::update_tx_samp_rate, this, mb, dspno, _1));
            _tree->create<double>(tx_dsp_path / "freq/value")
                .coerce(boost::bind(&tx_dsp_core_200::set_freq, _mbc[mb].tx_dsps[dspno], _1));
            _tree->create<meta_range_t>(tx_dsp_path / "freq/range")
                .publish(boost::bind(&tx_dsp_core_200::get_freq_range, _mbc[mb].tx_dsps[dspno]));
        }

        //setup dsp flow control
        const double ups_per_sec = device_args_i.cast<double>("ups_per_sec", 20);
        const size_t send_frame_size = _mbc[mb].tx_dsp_xports[0]->get_send_frame_size();
        const double ups_per_fifo = device_args_i.cast<double>("ups_per_fifo", 8.0);
        _mbc[mb].tx_dsps[0]->set_updates(
            (ups_per_sec > 0.0)? size_t(get_master_clock_rate()/*approx tick rate*//ups_per_sec) : 0,
            (ups_per_fifo > 0.0)? size_t(UMTRX_SRAM_BYTES/ups_per_fifo/send_frame_size) : 0
        );
        _mbc[mb].tx_dsps[1]->set_updates(
            (ups_per_sec > 0.0)? size_t(get_master_clock_rate()/*approx tick rate*//ups_per_sec) : 0,
            (ups_per_fifo > 0.0)? size_t(UMTRX_SRAM_BYTES/ups_per_fifo/send_frame_size) : 0
        );

        ////////////////////////////////////////////////////////////////
        // create time control objects
        ////////////////////////////////////////////////////////////////
        time64_core_200::readback_bases_type time64_rb_bases;
        time64_rb_bases.rb_secs_now = U2_REG_TIME64_SECS_RB_IMM;
        time64_rb_bases.rb_ticks_now = U2_REG_TIME64_TICKS_RB_IMM;
        time64_rb_bases.rb_secs_pps = U2_REG_TIME64_SECS_RB_PPS;
        time64_rb_bases.rb_ticks_pps = U2_REG_TIME64_TICKS_RB_PPS;
        _mbc[mb].time64 = time64_core_200::make(
            _mbc[mb].iface, U2_REG_SR_ADDR(SR_TIME64), time64_rb_bases, mimo_clock_sync_delay_cycles
        );
        _tree->access<double>(mb_path / "tick_rate")
            .subscribe(boost::bind(&time64_core_200::set_tick_rate, _mbc[mb].time64, _1));
        _tree->create<time_spec_t>(mb_path / "time/now")
            .publish(boost::bind(&time64_core_200::get_time_now, _mbc[mb].time64))
            .subscribe(boost::bind(&time64_core_200::set_time_now, _mbc[mb].time64, _1));
        _tree->create<time_spec_t>(mb_path / "time/pps")
            .publish(boost::bind(&time64_core_200::get_time_last_pps, _mbc[mb].time64))
            .subscribe(boost::bind(&time64_core_200::set_time_next_pps, _mbc[mb].time64, _1));
        //setup time source props
        _tree->create<std::string>(mb_path / "time_source/value")
            .subscribe(boost::bind(&time64_core_200::set_time_source, _mbc[mb].time64, _1));
        _tree->create<std::vector<std::string> >(mb_path / "time_source/options")
            .publish(boost::bind(&time64_core_200::get_time_sources, _mbc[mb].time64));
        //setup reference source props
      _tree->create<std::string>(mb_path / "clock_source/value");
//            .subscribe(boost::bind(&umtrx_impl::update_clock_source, this, mb, _1));

        static const std::vector<std::string> clock_sources = boost::assign::list_of("internal")("external")("mimo");
        _tree->create<std::vector<std::string> >(mb_path / "clock_source/options").set(clock_sources);

        ////////////////////////////////////////////////////////////////
        // create dboard control objects
        ////////////////////////////////////////////////////////////////

        // LMS dboard do not have physical eeprom so we just hardcode values from host/lib/usrp/dboard/db_lms.cpp
        dboard_eeprom_t rx_db_eeprom, tx_db_eeprom, gdb_eeprom;
        rx_db_eeprom.id = 0xfa07;
        rx_db_eeprom.revision = _mbc[mb].iface->mb_eeprom["revision"];
        tx_db_eeprom.id = 0xfa09;
        tx_db_eeprom.revision = _mbc[mb].iface->mb_eeprom["revision"];
        //gdb_eeprom.id = 0x0000;

        BOOST_FOREACH(const std::string &board, _mbc[mb].dbc.keys()){
            // Different serial numbers for each LMS on a UmTRX.
            // This is required to properly correlate calibration files to LMS chips.
            rx_db_eeprom.serial = _mbc[mb].iface->mb_eeprom["serial"] + "." + board;
            tx_db_eeprom.serial = _mbc[mb].iface->mb_eeprom["serial"] + "." + board;

            //create dboard interface
            _mbc[mb].dbc[board].dboard_iface = make_umtrx_dboard_iface(_mbc[mb].iface, board,
                                                                       2*get_master_clock_rate()); // ref_clk = 2 * sample rate
            _mbc[mb].dbc[board].dboard_manager = dboard_manager::make(
                rx_db_eeprom.id, tx_db_eeprom.id, gdb_eeprom.id,
                _mbc[mb].dbc[board].dboard_iface, _tree->subtree(mb_path / "dboards" / board)
                );

            //create the properties and register subscribers
            _tree->create<dboard_eeprom_t>(mb_path / "dboards" / board / "rx_eeprom")
                .set(rx_db_eeprom);

            _tree->create<dboard_eeprom_t>(mb_path / "dboards" / board / "tx_eeprom")
                .set(tx_db_eeprom);

            _tree->create<dboard_eeprom_t>(mb_path / "dboards" / board / "gdb_eeprom")
                .set(gdb_eeprom);
            
            _tree->create<dboard_iface::sptr>(mb_path / "dboards" / board / "iface").set(_mbc[mb].dbc[board].dboard_iface);

            //bind frontend corrections to the dboard freq props
            const fs_path db_tx_fe_path = mb_path / "dboards" / board / "tx_frontends";
            BOOST_FOREACH(const std::string &name, _tree->list(db_tx_fe_path)){
                _tree->access<double>(db_tx_fe_path / name / "freq" / "value")
                    .subscribe(boost::bind(&umtrx_impl::set_tx_fe_corrections, this, mb, board, _1));
            }
            const fs_path db_rx_fe_path = mb_path / "dboards" / board / "rx_frontends";
            BOOST_FOREACH(const std::string &name, _tree->list(db_rx_fe_path)){
                _tree->access<double>(db_rx_fe_path / name / "freq" / "value")
                    .subscribe(boost::bind(&umtrx_impl::set_rx_fe_corrections, this, mb, board, _1));
            }

            //set Tx DC calibration values, which are read from mboard EEPROM
            if (_mbc[mb].iface->mb_eeprom.has_key("tx-vga1-dc-i") and not _mbc[mb].iface->mb_eeprom["tx-vga1-dc-i"].empty()) {
                BOOST_FOREACH(const std::string &name, _tree->list(db_tx_fe_path)){
                    _tree->access<uint8_t>(db_tx_fe_path / name / "lms6002d/tx_dc_i/value")
                        .set(boost::lexical_cast<int>(_mbc[mb].iface->mb_eeprom["tx-vga1-dc-i"]));
                }
            }
            if (_mbc[mb].iface->mb_eeprom.has_key("tx-vga1-dc-q") and not _mbc[mb].iface->mb_eeprom["tx-vga1-dc-q"].empty()) {
                BOOST_FOREACH(const std::string &name, _tree->list(db_tx_fe_path)){
                    _tree->access<uint8_t>(db_tx_fe_path / name / "lms6002d/tx_dc_q/value")
                        .set(boost::lexical_cast<int>(_mbc[mb].iface->mb_eeprom["tx-vga1-dc-q"]));
                }
            }
        }

        //set TCXO DAC calibration value, which is read from mboard EEPROM
        if (_mbc[mb].iface->mb_eeprom.has_key("tcxo-dac") and not _mbc[mb].iface->mb_eeprom["tcxo-dac"].empty()) {
            _tree->create<uint16_t>(mb_path / "tcxo_dac/value")
                .subscribe(boost::bind(&umtrx_impl::set_tcxo_dac, this, mb, _1))
                .set(boost::lexical_cast<uint16_t>(_mbc[mb].iface->mb_eeprom["tcxo-dac"]));
        }
    }

    //initialize io handling
    this->io_init();

    //do some post-init tasks
    this->update_rates();
    BOOST_FOREACH(const std::string &mb, _mbc.keys()){
        fs_path root = "/mboards/" + mb;

        _tree->access<subdev_spec_t>(root / "rx_subdev_spec").set(subdev_spec_t("A:" + _tree->list(root / "dboards/A/rx_frontends").at(0)));
        _tree->access<subdev_spec_t>(root / "tx_subdev_spec").set(subdev_spec_t("A:" + _tree->list(root / "dboards/A/tx_frontends").at(0)));
        _tree->access<std::string>(root / "clock_source/value").set("internal");
        _tree->access<std::string>(root / "time_source/value").set("none");

        //GPS installed: use external ref, time, and init time spec
        if (_mbc[mb].gps.get() and _mbc[mb].gps->gps_detected()){
            UHD_MSG(status) << "Setting references to the internal GPSDO" << std::endl;
            _tree->access<std::string>(root / "time_source/value").set("external");
            _tree->access<std::string>(root / "clock_source/value").set("external");
            UHD_MSG(status) << "Initializing time to the internal GPSDO" << std::endl;
            _mbc[mb].time64->set_time_next_pps(time_spec_t(time_t(_mbc[mb].gps->get_sensor("gps_time").to_int()+1)));
        }
    }
}

umtrx_impl::~umtrx_impl(void){UHD_SAFE_CALL(
    BOOST_FOREACH(const std::string &mb, _mbc.keys()){
        _mbc[mb].tx_dsps[0]->set_updates(0, 0);
        _mbc[mb].tx_dsps[1]->set_updates(0, 0);
    }
)}

void umtrx_impl::set_mb_eeprom(const std::string &mb, const uhd::usrp::mboard_eeprom_t &mb_eeprom){
    mb_eeprom.commit(*(_mbc[mb].iface), mboard_eeprom_t::MAP_UMTRX);
}
/*
void usrp2_impl::set_db_eeprom(const std::string &mb, const std::string &type, const uhd::usrp::dboard_eeprom_t &db_eeprom){
    if (type == "rx") db_eeprom.store(*_mbc[mb].iface, USRP2_I2C_ADDR_RX_DB);
    if (type == "tx") db_eeprom.store(*_mbc[mb].iface, USRP2_I2C_ADDR_TX_DB);
    if (type == "gdb") db_eeprom.store(*_mbc[mb].iface, USRP2_I2C_ADDR_TX_DB ^ 5);
}

sensor_value_t umtrx_impl::get_mimo_locked(const std::string &mb){
    const bool lock = (_mbc[mb].iface->peek32(U2_REG_IRQ_RB) & (1<<10)) != 0;
    return sensor_value_t("MIMO", lock, "locked", "unlocked");
}

sensor_value_t umtrx_impl::get_ref_locked(const std::string &mb){
    const bool lock = (_mbc[mb].iface->peek32(U2_REG_IRQ_RB) & (1<<11)) != 0;
    return sensor_value_t("Ref", lock, "locked", "unlocked");
}
*/
void umtrx_impl::set_rx_fe_corrections(const std::string &mb, const std::string &board, const double lo_freq){
    apply_rx_fe_corrections(this->get_tree()->subtree("/mboards/" + mb), board, lo_freq);
}

void umtrx_impl::set_tx_fe_corrections(const std::string &mb, const std::string &board, const double lo_freq){
    apply_tx_fe_corrections(this->get_tree()->subtree("/mboards/" + mb), board, lo_freq);
}

void umtrx_impl::set_tcxo_dac(const std::string &mb, const uint16_t val){
    if (verbosity>0) printf("umtrx_impl::set_tcxo_dac(%d)\n", val);
    _mbc[mb].iface->write_spi(4, spi_config_t::EDGE_FALL, val, 16);
}
