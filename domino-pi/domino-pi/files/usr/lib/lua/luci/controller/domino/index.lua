--[[
This file is part of YunWebUI.

YunWebUI is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

As a special exception, you may use this file as part of a free software
library without restriction.  Specifically, if other files instantiate
templates or use macros or inline functions from this file, or you compile
this file and link it with other files to produce an executable, this
file does not by itself cause the resulting executable to be covered by
the GNU General Public License.  This exception does not however
invalidate any other reasons why the executable file might be covered by
the GNU General Public License.

Copyright 2013 Arduino LLC (http://www.arduino.cc/)
]]

module("luci.controller.domino.index", package.seeall)

local function file_exists(file)
  local f = io.open(file, "rb")
  if f then f:close() end
  return f ~= nil
end

local function lines_from(file)
  local lines = {}
  for line in io.lines(file) do
    lines[#lines + 1] = line
  end
  return lines
end

local function rfind(s, c)
  local last = 1
  while string.find(s, c, last, true) do
    last = string.find(s, c, last, true) + 1
  end
  return last
end

local function param(name)
  local val = luci.http.formvalue(name)
  if val then
    val = luci.util.trim(val)
    if string.len(val) > 0 then
      return val
    end
    return nil
  end
  return nil
end

local function not_nil_or_empty(value)
  return value and value ~= ""
end

local function check_update_file()
  local update_file = luci.util.exec("update-file-available")
  if update_file and string.len(update_file) > 0 then
    return update_file
  end
  return nil
end

function get_first(cursor, config, type, option)
  return cursor:get_first(config, type, option)
end

function set_first(cursor, config, type, option, value)
  cursor:foreach(config, type, function(s)
    if s[".type"] == type then
      cursor:set(config, s[".name"], option, value)
    end
  end)
end

local function set_list_first(cursor, config, type, option, value)
  cursor:foreach(config, type, function(s)
    if s[".type"] == type then
      cursor:set_list(config, s[".name"], option, value)
    end
  end)
end

function delete_first(cursor, config, type, option, value)
  cursor:foreach(config, type, function(s)
    if s[".type"] == type then
      cursor:delete(config, s[".name"], option)
    end
  end)
end

local function to_key_value(s)
  local parts = luci.util.split(s, ":")
  parts[1] = luci.util.trim(parts[1])
  parts[2] = luci.util.trim(parts[2])
  return parts[1], parts[2]
end

function http_error(code, text)
  luci.http.prepare_content("text/plain")
  luci.http.status(code)
  if text then
    luci.http.write(text)
  end
end

function read_gpg_pub_key()
  local gpg_pub_key_ascii_file = io.open("/etc/domino/domino_gpg.asc")
  local gpg_pub_key_ascii = gpg_pub_key_ascii_file:read("*a")
  gpg_pub_key_ascii_file:close()
  return string.gsub(gpg_pub_key_ascii, "\n", "\\n")
end

dec_params = ""

function decrypt_pgp_message()
  local pgp_message = luci.http.formvalue("pgp_message")
  if pgp_message then
    if #dec_params > 0 then
      return dec_params
    end

    local pgp_enc_file = io.open("/tmp/pgp_message.txt", "w+")
    pgp_enc_file:write(pgp_message)
    pgp_enc_file:close()

    local json_input = luci.util.exec("cat /tmp/pgp_message.txt | gpg --no-default-keyring --secret-keyring /etc/domino/domino_gpg.sec --keyring /etc/domino/domino_gpg.pub --decrypt")
    local json = require("luci.json")
    dec_params = json.decode(json_input)
    return dec_params
  end
  return nil
end

function timezone_file_parse_callback(line_parts, array)
  if line_parts[1] and line_parts[2] and line_parts[3] then
    table.insert(array, { label = line_parts[1], timezone = line_parts[2], code = line_parts[3] })
  end
end

function csv_to_array(text, callback)
  local array = {}
  local line_parts;
  local lines = string.split(text, "\n")
  for i, line in ipairs(lines) do
    line_parts = string.split(line, "\t")
    callback(line_parts, array)
  end
  return array
end

function config_first()
	local domino=require("luci.controller.domino.index")
	local is_first_time_setting_page = string.find(luci.http.getenv("PATH_INFO"), "/webpanel/first_time")
	need_first_time_setting = false
	local dec_params = luci.controller.domino.index.decrypt_pgp_message()
	local user = luci.http.formvalue("username") or (dec_params and dec_params["username"])
	local pass = luci.http.formvalue("password") or (dec_params and dec_params["password"])
	local hostname = luci.http.formvalue("hostname") or (dec_params and dec_params["hostname"])
	local zonename = luci.http.formvalue("zonename") or (dec_params and dec_params["zonename"])
	if (user and pass and hostname and zonename) then
		--now set basic config 
		local uci = luci.model.uci.cursor()
		uci:load("system")
		uci:load("wireless")
		uci:load("network")
		uci:load("dhcp")
		uci:load("domino")

		luci.sys.user.setpasswd("root", pass)

		local sha256 = require("luci.sha256")
		domino.set_first(uci, "domino", "domino", "password", sha256.sha256(pass))
		
		local host= string.gsub(hostname, " ", "_")
		domino.set_first(uci, "system", "system", "hostname", host)
		uci:set("network", "lan", "hostname", host)
		uci:set("network", "wan", "hostname", host)
		--uci:set("network", "wwan", "hostname", hostname)

		local function find_tz_regdomain(zonename)
		  local tz_regdomains = domino.csv_to_array(luci.util.exec("zcat /etc/domino/wifi_timezones.csv.gz"), domino.timezone_file_parse_callback)
		  for i, tz in ipairs(tz_regdomains) do
			if tz["label"] == zonename then
			  return tz
			end
		  end
		  return nil
		end

		local tz_regdomain = find_tz_regdomain(zonename)
		if tz_regdomain then
		  domino.set_first(uci, "system", "system", "timezone", tz_regdomain.timezone)
		  domino.set_first(uci, "system", "system", "zonename", zonename)
		  domino.delete_first(uci, "system", "system", "timezone_desc")
		end

		uci:commit("system")
		uci:commit("wireless")
		uci:commit("network")
		uci:commit("dhcp")
		uci:commit("domino")
		local ctx = {
			hostname = hostname,
			duration = 60,
			title = "Restarting",
			msg = "Please wait around 60 seconds to reconnect the network",
		}

		luci.template.render("domino/rebooting", ctx)
		luci.util.exec("reboot")
	else
		if not is_first_time_setting_page then
			--if requested other pages, redirect to first_time_setting
			local basic_auth = luci.http.getenv("HTTP_AUTHORIZATION")
		
			luci.http.redirect(luci.dispatcher.build_url("webpanel/first_time"))			
		else
			--if 
			local uci = luci.model.uci.cursor()
			uci:load("system")
			--uci:load("domino")

			local timezones_wifi_reg_domains = domino.csv_to_array(luci.util.exec("zcat /etc/domino/wifi_timezones.csv.gz"), domino.timezone_file_parse_callback)

			local zonename = domino.get_first(uci, "system", "system", "zonename")
			zonename = zonename or domino.get_first(uci, "system", "system", "timezone_desc")
			local ctx = {
				hostname = domino.get_first(uci, "system", "system", "hostname"),
				zonename = zonename,
				timezones_wifi_reg_domains = timezones_wifi_reg_domains,
				pub_key = luci.controller.domino.index.read_gpg_pub_key(),
			}
			luci.template.render("domino/first_time",ctx)
			need_first_time_setting = true
		end
	end
	return need_first_time_setting
end

function index()
	function luci.dispatcher.authenticator.arduinoauth(validator, accs, default)
		local domino=require("luci.controller.domino.index")
		local need_first_time_setting = false
		
		--if no password set yet, go to setting page
		if luci.sys.process.info("uid") == 0 and luci.sys.user.getuser("root") and not luci.sys.user.getpasswd("root") then
			need_first_time_setting=domino.config_first()
		end 
		
		--stop forwarding to login page, if we need to setup for the first time
		if need_first_time_setting then
			return
		end
		
		local dec_params = luci.controller.domino.index.decrypt_pgp_message()
		
		local user = luci.http.formvalue("username") or (dec_params and dec_params["username"])
		local pass = luci.http.formvalue("password") or (dec_params and dec_params["password"])
		local basic_auth = luci.http.getenv("HTTP_AUTHORIZATION")
		if user and validator(user, pass) then
		  return user
		end

		if basic_auth and basic_auth ~= "" then
		  local decoded_basic_auth = nixio.bin.b64decode(string.sub(basic_auth, 7))
		  user = string.sub(decoded_basic_auth, 0, string.find(decoded_basic_auth, ":") - 1)
		  pass = string.sub(decoded_basic_auth, string.find(decoded_basic_auth, ":") + 1)
		end

		if user then
		  if #pass ~= 64 and validator(user, pass) then
			return user
		  elseif #pass == 64 then
			local uci = luci.model.uci.cursor()
			uci:load("domino")
			local stored_encrypted_pass = uci:get_first("domino", "domino", "password")
			if pass == stored_encrypted_pass then
			  return user
			end
		  end
		end

		local url = luci.http.getenv("PATH_INFO")
		local is_webpanel = string.find(luci.http.getenv("PATH_INFO"), "/webpanel")

		if is_webpanel then
		  local gpg_pub_key_ascii = luci.controller.domino.index.read_gpg_pub_key()
		  luci.template.render("domino/set_password", { duser = default, fuser = user, pub_key = gpg_pub_key_ascii, login_failed = dec_params ~= nil })
		else
		  if user then
			luci.http.status(403)
		  else
			luci.http.header("WWW-Authenticate", "Basic realm=\"domino\"")
			luci.http.status(401)
		  end
		end
		return false
	end

	  local function make_entry(path, target, title, order)
		local page = entry(path, target, title, order)
		page.leaf = true
		return page
	  end

	  -- web panel
	  local webpanel = entry({ "webpanel" }, alias("webpanel", "go_to_homepage"), _("Domino Web Panel"), 10)
	  webpanel.sysauth = "root"
	  webpanel.sysauth_authenticator = "arduinoauth"

	  make_entry({ "webpanel", "homepage" }, call("homepage"), _("Domino Web Panel"), 10)
	  make_entry({ "webpanel", "go_to_homepage" }, call("go_to_homepage"), nil)
	  make_entry({ "webpanel", "set_password" }, call("go_to_homepage"), nil)
	  make_entry({ "webpanel", "first_time" }, call("go_to_homepage"), nil)
	  make_entry({ "webpanel", "config" }, call("config"), nil)
	  make_entry({ "webpanel", "devices" }, call("devices"), nil)
	  make_entry({ "webpanel", "network" }, call("network"), nil)
	  make_entry({ "webpanel", "wifi_detect" }, call("wifi_detect"), nil)
	  make_entry({ "webpanel", "rebooting" }, template("domino/rebooting"), nil)
	  make_entry({ "webpanel", "reset_board" }, call("reset_board"), nil)
	  make_entry({ "webpanel", "toogle_rest_api_security" }, call("toogle_rest_api_security"), nil)
	  make_entry({ "webpanel", "upload_sketch" }, call("upload_sketch"), nil)
	  make_entry({ "webpanel", "upload_firmware" }, call("upload_firmware"), nil)
	  make_entry({ "webpanel", "upgrade_firmware" }, call("upgrade_firmware"), nil)
	  make_entry({ "webpanel", "editor" }, call("editor"), nil)
	  make_entry({ "webpanel", "files" }, call("files"), nil)
	  make_entry({ "webpanel", "get_firmware_online" }, call("get_firmware_online"),nil)
	  make_entry({ "webpanel", "download_firmware_online" }, call("download_firmware_online"),nil)
	  
	  --api security level
	  local uci = luci.model.uci.cursor()
	  uci:load("domino")
	  local secure_rest_api = uci:get_first("domino", "domino", "secure_rest_api")
	  local rest_api_sysauth = false
	  if secure_rest_api == "true" then
		rest_api_sysauth = webpanel.sysauth
	  end

	  --storage api
	  local data_api = node("data")
	  data_api.sysauth = rest_api_sysauth
	  data_api.sysauth_authenticator = webpanel.sysauth_authenticator
	  make_entry({ "data", "get" }, call("storage_send_request"), nil).sysauth = rest_api_sysauth
	  make_entry({ "data", "put" }, call("storage_send_request"), nil).sysauth = rest_api_sysauth
	  make_entry({ "data", "delete" }, call("storage_send_request"), nil).sysauth = rest_api_sysauth
	  local mailbox_api = node("mailbox")
	  mailbox_api.sysauth = rest_api_sysauth
	  mailbox_api.sysauth_authenticator = webpanel.sysauth_authenticator
	  make_entry({ "mailbox" }, call("build_bridge_mailbox_request"), nil).sysauth = rest_api_sysauth

	  --plain socket endpoint
	  local plain_socket_endpoint = make_entry({ "arduino" }, call("board_plain_socket"), nil)
	  plain_socket_endpoint.sysauth = rest_api_sysauth
	  plain_socket_endpoint.sysauth_authenticator = webpanel.sysauth_authenticator
end

function go_to_homepage()
  luci.http.redirect(luci.dispatcher.build_url("webpanel/homepage"))
end

function fork_exec(command)
	local pid = nixio.fork()
	if pid > 0 then
		return
	elseif pid == 0 then
		-- change to root dir
		nixio.chdir("/")

		-- patch stdin, out, err to /dev/null
		local null = nixio.open("/dev/null", "w+")
		if null then
			nixio.dup(null, nixio.stderr)
			nixio.dup(null, nixio.stdout)
			nixio.dup(null, nixio.stdin)
			if null:fileno() > 2 then
				null:close()
			end
		end

		-- replace with target command
		nixio.exec("/bin/sh", "-c", command)
	end
end

function download_firmware_online()
	local uci = luci.model.uci.cursor()
	uci:load("domino")
	local board_type=uci:get_first("domino","domino","board")
	if not board_type then
		board_type="pi"
	end
	local firmware_bin="/tmp/firmware.bin"
	local function image_supported()
		-- XXX: yay...
		return ( 0 == os.execute(
			". /lib/functions.sh; " ..
			"include /lib/upgrade; " ..
			"platform_check_image %q >/dev/null"
				% firmware_bin
		) )
	end

	local function image_checksum()
		return (luci.sys.exec("md5sum %q" % firmware_bin):match("^([^%s]+)"))
	end
	
	local list=nixio.fs.readfile("/tmp/firmware_list.txt")
	local words=string.gmatch(list,"%S+")
	local version=words(1)
	local md5 = words(2)
	local file = words(3)
	local size = words(4)
	if not size then
		size="8388608"
	end
	local supported=false
	local percent = 0
	local querystring=luci.http.getenv("QUERY_STRING")
	local check = luci.http.protocol.urldecode_params(querystring, false)["check"]
	if not check then
		check = "0"
	end
	local done = false
	
	luci.http.prepare_content("application/json")
	local json = require("luci.json")
	
	if check == "0" then
		nixio.fs.remove(firmware_bin)
		local url
		if board_type == "pi" then
			url="http://domino.io/firmware/pi/"
		elseif board_type == "qi" then
			url="http://domino.io/firmware/qi/"
		end
		--luci.http.write("v:"..version..", md5:" .. md5 ..", file:" .. file .. ", size:" .. size)
		--luci.http.write("wget " ..url..file.." -O /tmp/firmware.bin.tmp && mv /tmp/firmware.bin.tmp /tmp/firmware.bin")
		fork_exec("wget " ..url..file.." -O /tmp/firmware.bin.tmp && mv /tmp/firmware.bin.tmp /tmp/firmware.bin");
	else
		local size_downloaded=nixio.fs.stat("/tmp/firmware.bin.tmp","size");
		if not size_downloaded then
			size_downloaded=nixio.fs.stat(firmware_bin,"size");
			if not size_downloaded then
				size_downloaded="0"
			else
				done = true;
			end
		end
		percent=tonumber(size_downloaded)/tonumber(size);
		
	end
	if done then
		supported=image_supported()
	end
	luci.http.write(json.encode({
					percent=percent,
					done = done,
					supported = supported
	}));
	
end

function get_firmware_online()
	local uci = luci.model.uci.cursor()
	uci:load("domino")
	local board_type=uci:get_first("domino","domino","board")
	if not board_type then
		board_type="pi"
	end
	
	local v_old=0
	local v_new=0
	local version
	local md5
	local file 
	local size
	
	local current_version=nixio.fs.readfile("/etc/domino_version")
	if current_version then
		local v_old=tonumber(string.match(string.gmatch(current_version,"%S+")(1),"%d.%d"))
	end

	local url
	local firmware
	if board_type == "pi" then
		url="http://domino.io/firmware/pi/"
	elseif board_type == "qi" then
		url="http://domino.io/firmware/qi/"
	end
	local info=luci.util.exec("wget " ..url.."list.txt -O -");
	if info then
		local words=string.gmatch(info,"%S+")
		if words then
			nixio.fs.writefile("/tmp/firmware_list.txt",info);
			version=words(1)
			md5 = words(2)
			file = words(3)
			size = words(4)
			-- version is like 2.10-note
			v_new=tonumber(string.match(version,"%d.%d"))
		end
	
	end
	
	local has_new = false
	if v_new > v_old then
		has_new = true
	end
	
	luci.http.prepare_content("application/json")
	local json = require("luci.json")
	luci.http.write(json.encode({
								version=version,
								md5=md5,
								file=file,
								new=has_new,
								size=size
								}
					))
	luci.http.write(json)
	
end

local function parse_date_from_command(command)
  local function AnIndexOf(t, val)
    for k, v in ipairs(t) do
      if v == val then return k end
    end
  end

  local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

  local date = luci.util.exec(command)

  if not date or #date == 0 then
    return 0
  end

  local month, day, hour, min, sec, year = date:match("%w+%s+(%w+)%s+(%d+)%s+(%d+):(%d+):(%d+)%s+%w+%s+(%d+)")
  return os.time({ year = year, month = AnIndexOf(months, month), day = day, hour = hour, min = min, sec = sec })
end

function homepage()
  local wa = require("luci.tools.webadmin")
  local network = luci.util.exec("LANG=en ifconfig | grep HWaddr")
  network = string.split(network, "\n")
  local ifnames = {}
  for i, v in ipairs(network) do
    local ifname = luci.util.trim(string.split(network[i], " ")[1])
    if not_nil_or_empty(ifname) and ifname ~= "br-lan" and ifname ~="eth1" then
      table.insert(ifnames, ifname)
    end
  end

  local ifaces_pretty_names = {
    wlan0 = "WiFi",
    eth0 = "Wired Ethernet"
  }

  local ifaces = {}
  for i, ifname in ipairs(ifnames) do

    local ix = luci.util.exec("LANG=en ifconfig " .. ifname)
    local mac = ix and ix:match("HWaddr ([^%s]+)") or "-"

    ifaces[ifname] = {
      mac = mac:upper(),
      pretty_name = ifaces_pretty_names[ifname]
    }

    local address = ix and ix:match("inet addr:([^%s]+)")
    local netmask = ix and ix:match("Mask:([^%s]+)")
    if address then
      ifaces[ifname]["address"] = address
      ifaces[ifname]["netmask"] = netmask
    end
  end

  local deviceinfo = luci.sys.net.deviceinfo()
  for k, v in pairs(deviceinfo) do
    if ifaces[k] then
      ifaces[k]["rx"] = v[1] and wa.byte_format(tonumber(v[1])) or "-"
      ifaces[k]["tx"] = v[9] and wa.byte_format(tonumber(v[9])) or "-"
    end
  end
  
  local uci = luci.model.uci.cursor()
  uci:load("domino")
  local board=uci:get_first("domino","domino","board")
  if not board then
	board="pi"
  end
  
  local function cam_configured_port(cam)
    local port="0"
	uci:foreach("mjpg-streamer", "mjpg-streamer", function(s)
			if s["device"] == cam then
				port = s["port"]
			end
		end)
	return port
  end
  
  local disks=luci.sys.mounts()
  --get configured cameras
  local cameras=nixio.fs.glob("/dev/video*")
  local cam_configured={}
  uci:load("mjpg-streamer")

  if cameras then
	for camera in cameras do
		local port=cam_configured_port(camera)
		table.insert(cam_configured,{device=camera,port=port})
	end
  end
  --check if mjpg-steramer is installed and up
  local processes=luci.sys.process.list()
  local mjpg=false
  local mjpg_process=luci.util.exec("ps|grep mjpg_streamer|grep -v grep")
  if mjpg_process ~= "" then
	mjpg=true
  end

  local ctx = {
	board = board,
    hostname = luci.sys.hostname(),
    ifaces = ifaces,
	disks = disks,
	cameras= cam_configured,
	mjpg=mjpg
  }

  --Traslates status codes extracted from include/linux/ieee80211.h to a more friendly version
  local function parse_dmesg(lines)
    local function get_error_message_from(file_suffix, code)
      local function wifi_error_message_code_callback(line_parts, array)
        if line_parts[1] and line_parts[2] then
          table.insert(array, { message = line_parts[1], code = tonumber(line_parts[2]) })
        end
      end

      local wifi_errors = csv_to_array(luci.util.exec("zcat /etc/domino/wifi_error_" .. file_suffix .. ".csv.gz"), wifi_error_message_code_callback)
      for idx, wifi_error in ipairs(wifi_errors) do
        if code == wifi_error.code then
          return lines, wifi_error.message
        end
      end
      return lines, nil
    end

    local function find_dmesg_wifi_error_reason(lines)
      for idx, line in ipairs(lines) do
        if string.find(line, "disassociated from") then
          return string.match(line, "Reason: (%d+)")
        end
      end
      return nil
    end

    local code = tonumber(find_dmesg_wifi_error_reason(lines))
    if code then
      return get_error_message_from("reasons", code)
    end

    local function find_dmesg_wifi_error_status(lines)
      for idx, line in ipairs(lines) do
        if string.find(line, "denied authentication") then
          return string.match(line, "status (%d+)")
        end
      end
      return nil
    end

    code = tonumber(find_dmesg_wifi_error_status(lines))
    if code then
      return get_error_message_from("statuses", code)
    end

    return lines, nil
  end

  if file_exists("/last_dmesg_with_wifi_errors.log") then
    local lines, error_message = parse_dmesg(lines_from("/last_dmesg_with_wifi_errors.log"))
    ctx["last_log"] = lines
    ctx["last_log_error_message"] = error_message
  end

  if file_exists("/usr/bin/extract-built-date") then
    ctx["current_build_date"] = parse_date_from_command("extract-built-date /etc/domino/domino-release")
  end

  local update_file = check_update_file()
  if update_file then
    ctx["update_file"] = update_file

    if file_exists("/usr/bin/extract-built-date-from-sysupgrade-image") and ctx["current_build_date"] then
      local update_file_build_date = parse_date_from_command("extract-built-date-from-sysupgrade-image " .. update_file)
      if update_file_build_date > 0 then
        ctx["update_file_build_date"] = update_file_build_date

        ctx["update_file_newer"] = os.difftime(ctx["current_build_date"], update_file_build_date) < 0
      end
    end
  end

  luci.template.render("domino/homepage", ctx)
end


function config_get()
  local uci = luci.model.uci.cursor()
  uci:load("system")
  uci:load("wireless")
  uci:load("domino")
  local firmware_version=nixio.fs.readfile("/etc/domino_version")
  local timezones_wifi_reg_domains = csv_to_array(luci.util.exec("zcat /etc/domino/wifi_timezones.csv.gz"), timezone_file_parse_callback)


  local rest_api_is_secured = uci:get_first("domino", "domino", "secure_rest_api") == "true"

  local zonename = get_first(uci, "system", "system", "zonename")
  zonename = zonename or get_first(uci, "system", "system", "timezone_desc")
  local ctx = {
    hostname = get_first(uci, "system", "system", "hostname"),
    zonename = zonename,
    timezones_wifi_reg_domains = timezones_wifi_reg_domains,
    pub_key = luci.controller.domino.index.read_gpg_pub_key(),
    rest_api_is_secured = rest_api_is_secured,
    firmware_version=firmware_version
  }

  luci.template.render("domino/config", ctx)
end

function devices_get()
	
	luci.template.render("domino/devices", ctx)
end

function editor_get()
	local querystring=luci.http.getenv("QUERY_STRING")
	local path = luci.http.protocol.urldecode_params(querystring, false)["path"]
	local content = nixio.fs.readfile(path)
	--pub_key = luci.controller.domino.index.read_gpg_pub_key(),
	ctx={
		path= path,
		content = content
	}
	luci.template.render("domino/editor", ctx)
end

function editor_post()
	local contents= luci.http.formvalue("contents")
	--remove windows newline \r from contents
	contents = string.gsub(contents,"\r","")
	local querystring=luci.http.getenv("QUERY_STRING")
	local path = luci.http.protocol.urldecode_params(querystring, false)["path"]
	nixio.fs.writefile(path,contents)
	local content = nixio.fs.readfile(path)
	--pub_key = luci.controller.domino.index.read_gpg_pub_key(),
	ctx={
		path= path,
		content = content
	}
	luci.template.render("domino/editor", ctx)
end

function editor()
  if luci.http.getenv("REQUEST_METHOD") == "POST" then
    editor_post()
  else
    editor_get()
  end
end

function files_post()

end

function sort_files(a,b)
	return a["type"] < b["type"]
end

function files_get ()
	local querystring=luci.http.getenv("QUERY_STRING")
	local base_dir = luci.http.protocol.urldecode_params(querystring, false)["path"]
	if base_dir ==nil then
		base_dir = "/"
	end
	if (string.sub(base_dir,-2,-1) ~= "/") then
		base_dir = base_dir .. "/"
	end
	local files={}
	
	local file_list=nixio.fs.dir(base_dir)
	for entry in file_list do
		local stat = nixio.fs.stat(base_dir .. entry)
		if stat then 
			local size = stat["size"]
			local mtime = stat["mtime"]
			local file_type = stat["type"]
			table.insert(files,{fullpath = entry, size = size, mtime = mtime, type = file_type})
		end
	end
	
	local ctx = {
		--files=table.sort(files,sort_files),
		files=files,
		path=base_dir,
	}
	luci.template.render("domino/files", ctx)
end 

function files()
  if luci.http.getenv("REQUEST_METHOD") == "POST" then
    files_post()
  else
    files_get()
  end
end

function network_get()
	local uci = luci.model.uci.cursor()
	uci:load("network")
	uci:load("wireless")

	local timezones_wifi_reg_domains = csv_to_array(luci.util.exec("zcat /etc/domino/wifi_timezones.csv.gz"), timezone_file_parse_callback)

	local encryptions = {}
	encryptions[1] = { code = "none", label = "None" }
	encryptions[2] = { code = "wep", label = "WEP" }
	encryptions[3] = { code = "psk", label = "WPA" }
	encryptions[4] = { code = "psk2", label = "WPA2" }
	encryptions[5] = { code = "psk-mixed", label = "WPA/WPA2" }

	local uci = luci.model.uci.cursor()
	--uci:load("domino")
	--local rest_api_is_secured = uci:get_first("domino", "domino", "secure_rest_api") == "true"

	local zonename = get_first(uci, "system", "system", "zonename")
	zonename = zonename or get_first(uci, "system", "system", "timezone_desc")
	local modems = nixio.fs.glob("/dev/modem") and nixio.fs.glob("/dev/ttyUSB*")
	
	local usb=luci.util.exec("ifconfig -a|grep usb0")
	if usb and usb ~="" then
		usb="usb0"
	end
	local protocol = uci:get("network", "wan", "proto")
	--local wwan=uci:get("network","wwan")
	local wan_ifname=uci:get("network","wan","ifname")
	local sta=uci:get("wireless","sta")
	local sta_network=uci:get("wireless","sta","network")
	if(not wan_ifname and sta and sta_network=="wan") then
		protocol="wifi";
	end
	if wan_ifname == "usb0" and protocol=="dhcp" then
		protocol="usb"
	end
	local device = uci:get( "network", "wan", "device")
	if protocol=="usb" then
		device = uci:get("network","wan","ifname")
	end
	
	--get the first ap----------
	local ap=uci:get("wireless","ap")
	local ap_name=''
	if ap then
		ap_name="ap"
	else
		uci:foreach("wireless", "wifi-iface", function(s)
			if s["mode"] == "ap" then
				ap_name=s[".name"]
			end
		end)
	end
	
	local radio_diabled=uci:get("wireless","radio0","disabled")
	local ap_disabled=uci:get("wireless",ap_name,"disabled")
	local ap_enabled=true
	if(radio_disabled == "1" or ap_disabled == "1") then
		ap_enabled=false 
	end
	
	local ctx = {
		wan={
			protocol = protocol,
			ipaddr = uci:get( "network", "wan", "ipaddr"),
			netmask = uci:get( "network", "wan", "netmask"),
			gateway = uci:get( "network", "wan", "gateway"),
			dns = uci:get( "network", "wan", "ipaddr"),
			username = uci:get( "network", "wan", "username"),
			--password = uci:get( "network", "wan", "password"),
			apn = uci:get( "network", "wan", "apn"),
			pin = uci:get( "network", "wan", "pincode"),
			dialnumber = uci:get( "network", "wan", "dialnumber"),
			device = device,
			service = uci:get( "network", "wan", "service"),
			dns = uci:get( "network", "wan", "dns"),
			modems = modems,
			usb = usb,
			ssid=uci:get("wireless","sta","ssid"),
			--key=uci:get("wireless","sta","key"),
			encryption=uci:get("wireless","sta","encryption"),
		},
		lan = {
			ipaddr = uci:get("network","lan","ipaddr"),
		},
		wifi = {
			enabled = ap_enabled,
			mode = uci:get("wireless", ap_name, "mode"),
			ssid = uci:get("wireless", ap_name, "ssid"),
			encryption = uci:get("wireless", ap_name, "encryption"),
			--password = uci:get("wireless", ap_name, "key"),
		},
		--timezones_wifi_reg_domains = timezones_wifi_reg_domains,
		encryptions = encryptions,
		pub_key = luci.controller.domino.index.read_gpg_pub_key(),
		rest_api_is_secured = rest_api_is_secured
	}
	
	luci.template.render("domino/network", ctx)
end

function join_wifi(uci,ssid, encryption, password)
	--local uci = luci.model.uci.cursor()
	if ssid and encryption then
		uci:section("wireless","wifi-iface","sta")
		uci:set("wireless","sta","mode","sta")
		uci:set("wireless","sta","device","radio0")
		uci:set("wireless", "radio0", "channel", "auto")
		--set_first(uci, "wireless", "wifi-iface", "mode", "sta")
		--set_first(uci, "domino", "wifi-iface", "mode", "sta")

		if ssid then
			uci:set("wireless","sta", "ssid",ssid)
		end
		if encryption then
			uci:set("wireless","sta", "encryption", encryption)
		end
		if password then
			uci:set("wireless","sta", "key", password)
		end
		
		uci:set("wireless","sta","network","wan")
		uci:delete("network","wan","ifname")
		uci:set("network","wan","proto","dhcp")
		--uci:section("network","network","wwan")
		--uci:set("network","wwan","interface")
		--uci:set("network","wwan","proto","dhcp")
		
		--firewall configure-------------
	end

end

function network_post()
	local params = decrypt_pgp_message()

	local uci = luci.model.uci.cursor()
	uci:load("wireless")
	uci:load("network")
	uci:load("dhcp")
	uci:load("domino")
	
	--read old settings----------------
	local old_lan_ip=uci:get("network","lan","ipaddr")
	local old_wan_proto=uci:get("network","wan","proto")
	local old_wan_ipaddr=uci:get("network","wan","ipaddr")
	local old_wan_netmask=uci:get("network","wan","netmask")
	local old_wan_gateway=uci:get("network","wan","gateway")
	local old_wan_dns=uci:get("network","wan","dns")
	
	--get the first ap----------
	local ap=uci:get("wireless","ap")
	local ap_name=''
	if ap then
		ap_name="ap"
	else
		uci:foreach("wireless", "wifi-iface", function(s)
			if s["mode"] == "ap" then
				ap_name=s[".name"]
			end
		end)
	end
	
	--setup wan------------------------
	local wan_protocol=params["wan_protocol"]
	
	if wan_protocol ~= "static" then
		uci:delete("network","wan","ipaddr")
		uci:delete("network","wan","netmask")
		uci:delete("network","wan","gateway")
		uci:delete("network","wan","dns")
	end
	if wan_protocol ~= "3g" then
		uci:delete("network","wan","device")
		uci:delete("network","wan","service")
		uci:delete("network","wan","pincode")
		uci:delete("network","wan","apn")
		uci:delete("network","wan","dianumber")
	end
	if wan_protocol ~="3g" and wan_proto ~="pppoe" then
		uci:delete("network","wan","username")
		uci:delete("network","wan","password")
	end
	
	if wan_protocol ~= "wifi" then
		--delete sta
		uci:delete("wireless","sta")
	end
	
	if wan_protocol=="dhcp" then
		uci:set("network","wan","interface")
		uci:set("network","wan","proto","dhcp")
		uci:set("network","wan","ifname","eth0")
		uci:delete("network","wwan")
		uci:delete("wireless","sta")
	elseif wan_protocol=="static" then
		uci:set("network","wan","proto","static")
		uci:set("network","wan","ipaddr",params["ipaddr"])
		uci:set("network","wan","netmask",params["netmask"])
		uci:set("network","wan","gateway",params["gateway"])
		uci:set("network","wan","dns",params["dns"])
	elseif wan_protocol=="pppoe" then
		uci:set("network","wan","proto","pppoe")
		uci:set("network","wan","username",params["username"])
		uci:set("network","wan","password",params["password"])
	elseif wan_protocol=="3g" then
		uci:set("network","wan","proto","3g");
		uci:set("network","wan","username",params["username"])
		uci:set("network","wan","password",params["password"])
		uci:set("network","wan","device",params["modem"])
		uci:set("network","wan","service",params["service"])
		uci:set("network","wan","pincode",params["pin"])
		uci:set("network","wan","apn",params["apn"])
		--uci:set("network","wan","dianumber",params["dianumber"])
	elseif wan_protocol=="wifi" then
		local ssid=params["wifi_ssid"]
		local encryption=params["wifi_encryption"]
		local password
		if not_nil_or_empty(params["wifi_password"]) then
			password=params["wifi_password"]
		end
		join_wifi(uci,ssid, encryption, password)
	elseif wan_protocol=="usb" then
		uci:set("network","wan","proto","dhcp");
		uci:set("network","wan","ifname",params["phone"])
	end
	
	--setup lan------------------------
	local lan_ip_changed = false
	if old_lan_ip ~= params["lan_ip"] then
		uci:set("network","lan","ipaddr",params["lan_ip"])
		lan_ip_changed=true
	end

	--setup wifi ----------------------
	if(params["ap_enable"]) then
		uci:set("wireless",ap_name,"disabled",'0')
		uci:set("wireless","radio0","disabled",'0')
		uci:set("wireless",ap_name,"ssid",params["ap_ssid"])
		if not_nil_or_empty(params["ap_password"]) then
			uci:set("wireless",ap_name,"key",params["ap_password"])
		end
		uci:set("wireless",ap_name,"encryption",params["ap_encryption"])
	else
		uci:set("wireless",ap_name,"disabled",'1')
	end
	
	uci:commit("system")
	uci:commit("wireless")
	uci:commit("network")
	uci:commit("dhcp")
	uci:commit("domino")
	
	luci.util.exec("/etc/init.d/network restart");
	if lan_ip_changed then
		luci.util.exec("/etc/init.d/dnsmasq restart");
	end

	network_get()
	
end

function first_time()
  local params = decrypt_pgp_message()

  local uci = luci.model.uci.cursor()
  uci:load("system")
  uci:load("wireless")
  uci:load("network")
  uci:load("dhcp")
  uci:load("domino")

  if not_nil_or_empty(params["password"]) then
    local password = params["password"]
    luci.sys.user.setpasswd("root", password)

    local sha256 = require("luci.sha256")
    set_first(uci, "domino", "domino", "password", sha256.sha256(password))
  end

  if not_nil_or_empty(params["hostname"]) then
    local hostname = string.gsub(params["hostname"], " ", "_")
    set_first(uci, "system", "system", "hostname", hostname)
    uci:set("network", "lan", "hostname", hostname)
    uci:set("network", "wan", "hostname", hostname)
	--uci:set("network", "wwan", "hostname", hostname)
  end

  if params["zonename"] then
    local function find_tz_regdomain(zonename)
      local tz_regdomains = csv_to_array(luci.util.exec("zcat /etc/domino/wifi_timezones.csv.gz"), timezone_file_parse_callback)
      for i, tz in ipairs(tz_regdomains) do
        if tz["label"] == zonename then
          return tz
        end
      end
      return nil
    end

    local tz_regdomain = find_tz_regdomain(params["zonename"])
    if tz_regdomain then
      set_first(uci, "system", "system", "timezone", tz_regdomain.timezone)
      set_first(uci, "system", "system", "zonename", params["zonename"])
      delete_first(uci, "system", "system", "timezone_desc")
      params["wifi.country"] = tz_regdomain.code
    end
  end

  uci:commit("system")
  uci:commit("wireless")
  uci:commit("network")
  uci:commit("dhcp")
  uci:commit("domino")

  --[[
    local new_httpd_conf = ""
    for line in io.lines("/etc/httpd.conf") do
      if string.find(line, "C:192.168") == 1 then
        line = "#" .. line
      end
      new_httpd_conf = new_httpd_conf .. line .. "\n"
    end
    local new_httpd_conf_file = io.open("/etc/httpd.conf", "w+")
    new_httpd_conf_file:write(new_httpd_conf)
    new_httpd_conf_file:close()
  ]]
  luci.http.redirect(luci.dispatcher.build_url("webpanel/homepage"))

  --local ctx = {
  --  hostname = get_first(uci, "system", "system", "hostname"),
    
  --}

  --luci.template.render("domino/config", ctx)
  --luci.template.render("domino/rebooting", ctx)

  --luci.util.exec("reboot")
end

function config_post()
  local params = decrypt_pgp_message()
  local hostname
  local uci = luci.model.uci.cursor()
  uci:load("system")
  uci:load("wireless")
  uci:load("network")
  uci:load("dhcp")
  uci:load("domino")

  if not_nil_or_empty(params["password"]) then
    local password = params["password"]
    luci.sys.user.setpasswd("root", password)

    local sha256 = require("luci.sha256")
    set_first(uci, "domino", "domino", "password", sha256.sha256(password))
  end

  if not_nil_or_empty(params["hostname"]) then
    hostname = string.gsub(params["hostname"], " ", "_")
    set_first(uci, "system", "system", "hostname", hostname)
    uci:set("network", "lan", "hostname", hostname)
    uci:set("network", "wan", "hostname", hostname)
	--uci:set("network", "wwan", "hostname", hostname)
  end

  if params["zonename"] then
    local function find_tz_regdomain(zonename)
      local tz_regdomains = csv_to_array(luci.util.exec("zcat /etc/domino/wifi_timezones.csv.gz"), timezone_file_parse_callback)
      for i, tz in ipairs(tz_regdomains) do
        if tz["label"] == zonename then
          return tz
        end
      end
      return nil
    end

    local tz_regdomain = find_tz_regdomain(params["zonename"])
    if tz_regdomain then
      set_first(uci, "system", "system", "timezone", tz_regdomain.timezone)
      set_first(uci, "system", "system", "zonename", params["zonename"])
      delete_first(uci, "system", "system", "timezone_desc")
      params["wifi.country"] = tz_regdomain.code
    end
  end

  uci:commit("system")
  uci:commit("wireless")
  uci:commit("network")
  uci:commit("dhcp")
  uci:commit("domino")

  --[[
    local new_httpd_conf = ""
    for line in io.lines("/etc/httpd.conf") do
      if string.find(line, "C:192.168") == 1 then
        line = "#" .. line
      end
      new_httpd_conf = new_httpd_conf .. line .. "\n"
    end
    local new_httpd_conf_file = io.open("/etc/httpd.conf", "w+")
    new_httpd_conf_file:write(new_httpd_conf)
    new_httpd_conf_file:close()
  ]]

  local ctx = {
    hostname = hostname,
    duration = 60,
	title = "Restarting",
	msg = "Please wait around 60 seconds to reconnect the network"
  }

  --luci.template.render("domino/config", ctx)
  luci.template.render("domino/rebooting", ctx)

  luci.util.exec("reboot")
end

function config()
  if luci.http.getenv("REQUEST_METHOD") == "POST" then
    config_post()
  else
    config_get()
  end
end

function devices()
  if luci.http.getenv("REQUEST_METHOD") == "POST" then
    devices_post()
  else
    devices_get()
  end
end

function network()
  if luci.http.getenv("REQUEST_METHOD") == "POST" then
    network_post()
  else
    network_get()
  end
end

function wifi_detect()
  local sys = require("luci.sys")
  local iw = sys.wifi.getiwinfo("radio0")
  local wifis = iw.scanlist
  local result = {}
  for idx, wifi in ipairs(wifis) do
    if not_nil_or_empty(wifi.ssid) then
      local name = wifi.ssid
      local encryption = "none"
      local pretty_encryption = "None"
      if wifi.encryption.wep then
        encryption = "wep"
        pretty_encryption = "WEP"
      elseif wifi.encryption.wpa == 1 then
        encryption = "psk"
        pretty_encryption = "WPA"
      elseif wifi.encryption.wpa >= 2 then
        encryption = "psk2"
        pretty_encryption = "WPA2"
      end
      local signal_strength = math.floor(wifi.quality * 100 / wifi.quality_max)
      table.insert(result, { name = name, encryption = encryption, pretty_encryption = pretty_encryption, signal_strength = signal_strength })
    end
  end

  luci.http.prepare_content("application/json")
  local json = require("luci.json")
  luci.http.write(json.encode(result))
end

function reset_board()
  local update_file = check_update_file()
  if param("button") and update_file then
    local ix = luci.util.exec("LANG=en ifconfig wlan0 | grep HWaddr")
    local macaddr = string.gsub(ix:match("HWaddr ([^%s]+)"), ":", "")

    luci.template.render("domino/board_reset", { name = "Domino " .. macaddr })

    luci.util.exec("blink-start 50")
    luci.util.exec("run-sysupgrade " .. update_file)
  end
end

function toogle_rest_api_security()
  local uci = luci.model.uci.cursor()
  uci:load("domino")

  local rest_api_secured = luci.http.formvalue("rest_api_secured")
  if rest_api_secured == "true" then
    set_first(uci, "domino", "domino", "secure_rest_api", "true")
  else
    set_first(uci, "domino", "domino", "secure_rest_api", "false")
  end

  uci:commit("domino")
end

function upload_sketch()
  local sketch_hex = "/tmp/sketch.hex"

  local chunk_number = 0

  local fp
  luci.http.setfilehandler(function(meta, chunk, eof)
    if not fp then
      fp = io.open(sketch_hex, "w")
    end
    if chunk then
      chunk_number = chunk_number + 1
      fp:write(chunk)
    end
    if eof then
      chunk_number = chunk_number + 1
      fp:close()
    end
  end)

  local sketch = luci.http.formvalue("sketch_hex")
  if sketch and #sketch > 0 and rfind(sketch, ".hex") > 1 then
    local merge_output = luci.util.exec("merge-sketch-with-bootloader.lua " .. sketch_hex .. " 2>&1")
    local kill_bridge_output = luci.util.exec("kill-bridge 2>&1")
    local run_avrdude_output = luci.util.exec("run-avrdude /tmp/sketch.hex '-q -q' 2>&1")

    local ctx = {
      merge_output = merge_output,
      kill_bridge_output = kill_bridge_output,
      run_avrdude_output = run_avrdude_output
    }
    luci.template.render("domino/upload", ctx)
  else
    luci.http.redirect(luci.dispatcher.build_url("webpanel/homepage"))
  end
end

function upgrade_firmware()
	local firmware_bin="/tmp/firmware.bin"
	local function image_supported()
		-- XXX: yay...
		return ( 0 == os.execute(
			". /lib/functions.sh; " ..
			"include /lib/upgrade; " ..
			"platform_check_image %q >/dev/null"
				% firmware_bin
		) )
	end

	local function image_checksum()
		return (luci.sys.exec("md5sum %q" % firmware_bin):match("^([^%s]+)"))
	end

	local keep = (luci.http.formvalue("keep") == "1") and "" or "-n"
	luci.template.render("domino/rebooting",  {
		title = luci.i18n.translate("Flashing..."),
		duration = 120,
		msg   = luci.i18n.translate("The system is flashing now.<br /> DO NOT POWER OFF THE DEVICE!<br /> Wait a few minutes before you try to reconnect. It might be necessary to renew the address of your computer to reach the device again, depending on your settings."),
		addr  = (#keep > 0) and "192.168.1.1" or nil,
		hostname = luci.sys.hostname()
	})
	fork_exec("killall dropbear uhttpd; sleep 1; /sbin/sysupgrade %s %q" %{ keep, firmware_bin })
end

function upload_firmware()
  local firmware_bin = "/tmp/firmware.bin"

  local chunk_number = 0

  local fp
  luci.http.setfilehandler(
	function(meta, chunk, eof)
		if not fp then
		  fp = io.open(firmware_bin, "w")
		  --luci.http.write(meta.name)
		end
		if chunk then
		  chunk_number = chunk_number + 1
		  fp:write(chunk)
		end
		if eof then
		  chunk_number = chunk_number + 1
		  fp:close()
		end
	end
  )
  
	local function image_supported()
		-- XXX: yay...
		return ( 0 == os.execute(
			". /lib/functions.sh; " ..
			"include /lib/upgrade; " ..
			"platform_check_image %q >/dev/null"
				% firmware_bin
		) )
	end

	local function image_checksum()
		return (luci.sys.exec("md5sum %q" % firmware_bin):match("^([^%s]+)"))
	end
	
    local firmware = luci.http.formvalue("firmware")
	luci.http.prepare_content("application/json")
	if image_supported() then
		luci.http.write_json({supported=true})
	else
		luci.http.write_json({supported=false})
	end
end

local function build_bridge_request(command, params)

  local bridge_request = {
    command = command
  }

  if command == "raw" then
    params = table.concat(params, "/")
    if not_nil_or_empty(params) then
      bridge_request["data"] = params
    end
    return bridge_request
  end

  if command == "get" then
    if not_nil_or_empty(params[1]) then
      bridge_request["key"] = params[1]
    end
    return bridge_request
  end

  if command == "put" and not_nil_or_empty(params[1]) and params[2] then
    bridge_request["key"] = params[1]
    bridge_request["value"] = params[2]
    return bridge_request
  end

  if command == "delete" and not_nil_or_empty(params[1]) then
    bridge_request["key"] = params[1]
    return bridge_request
  end

  return nil
end

local function extract_jsonp_param(query_string)
  if not not_nil_or_empty(query_string) then
    return nil
  end

  local qs_parts = string.split(query_string, "&")
  for idx, value in ipairs(qs_parts) do
    if string.find(value, "jsonp") == 1 or string.find(value, "callback") == 1 then
      return string.sub(value, string.find(value, "=") + 1)
    end
  end
end

local function parts_after(url_part)
  local url = luci.http.getenv("PATH_INFO")
  local url_after_part = string.find(url, "/", string.find(url, url_part) + 1)
  if not url_after_part then
    return {}
  end
  return luci.util.split(string.sub(url, url_after_part + 1), "/")
end

function storage_send_request()
  local method = luci.http.getenv("REQUEST_METHOD")
  local jsonp_callback = extract_jsonp_param(luci.http.getenv("QUERY_STRING"))
  local parts = parts_after("data")
  local command = parts[1]
  if not command or command == "" then
    luci.http.status(404)
    return
  end
  local params = {}
  for idx, param in ipairs(parts) do
    if idx > 1 and not_nil_or_empty(param) then
      table.insert(params, param)
    end
  end

  -- TODO check method?
  local bridge_request = build_bridge_request(command, params)
  if not bridge_request then
    luci.http.status(403)
    return
  end

  local uci = luci.model.uci.cursor()
  uci:load("domino")
  local socket_timeout = uci:get_first("domino", "domino", "socket_timeout", 5)

  local sock, code, msg = nixio.connect("127.0.0.1", 5700)
  if not sock then
    code = code or ""
    msg = msg or ""
    http_error(500, "nil socket, " .. code .. " " .. msg)
    return
  end

  sock:setopt("socket", "sndtimeo", socket_timeout)
  sock:setopt("socket", "rcvtimeo", socket_timeout)
  sock:setopt("tcp", "nodelay", 1)

  local json = require("luci.json")

  sock:write(json.encode(bridge_request))
  sock:writeall("\n")

  local response_text = {}
  while true do
    local bytes = sock:recv(4096)
    if bytes and #bytes > 0 then
      table.insert(response_text, bytes)
    end

    local json_response = json.decode(table.concat(response_text))
    if json_response then
      sock:close()
      luci.http.status(200)
      if jsonp_callback then
        luci.http.prepare_content("application/javascript")
        luci.http.write(jsonp_callback)
        luci.http.write("(")
        luci.http.write_json(json_response)
        luci.http.write(");")
      else
        luci.http.prepare_content("application/json")
        luci.http.write(json.encode(json_response))
      end
      return
    end

    if not bytes or #response_text == 0 then
      sock:close()
      http_error(500, "Empty response")
      return
    end
  end

  sock:close()
end

function board_plain_socket()
  local function send_response(response_text, jsonp_callback)
    if not response_text then
      luci.http.status(500)
      return
    end

    local rows = luci.util.split(response_text, "\r\n")
    if #rows == 1 or string.find(rows[1], "Status") ~= 1 then
      luci.http.prepare_content("text/plain")
      luci.http.status(200)
      luci.http.write(response_text)
      return
    end

    local body_start_at_idx = -1
    local content_type = "text/plain"
    for idx, row in ipairs(rows) do
      if row == "" then
        body_start_at_idx = idx
        break
      end

      local key, value = to_key_value(row)
      if string.lower(key) == "status" then
        luci.http.status(tonumber(value))
      elseif string.lower(key) == "content-type" then
        content_type = value
      else
        luci.http.header(key, value)
      end
    end

    local response_body = table.concat(rows, "\r\n", body_start_at_idx + 1)
    if content_type == "application/json" and jsonp_callback then
      local json = require("luci.json")
      luci.http.prepare_content("application/javascript")
      luci.http.write(jsonp_callback)
      luci.http.write("(")
      luci.http.write_json(json.decode(response_body))
      luci.http.write(");")
    else
      luci.http.prepare_content(content_type)
      luci.http.write(response_body)
    end
  end

  local method = luci.http.getenv("REQUEST_METHOD")
  local jsonp_callback = extract_jsonp_param(luci.http.getenv("QUERY_STRING"))
  local parts = parts_after("arduino")
  local params = {}
  for idx, param in ipairs(parts) do
    if not_nil_or_empty(param) then
      table.insert(params, param)
    end
  end

  if #params == 0 then
    luci.http.status(404)
    return
  end

  params = table.concat(params, "/")

  local uci = luci.model.uci.cursor()
  uci:load("domino")
  local socket_timeout = uci:get_first("domino", "domino", "socket_timeout", 5)

  local sock, code, msg = nixio.connect("127.0.0.1", 5555)
  if not sock then
    code = code or ""
    msg = msg or ""
    http_error(500, "Could not connect to YunServer " .. code .. " " .. msg)
    return
  end

  sock:setopt("socket", "sndtimeo", socket_timeout)
  sock:setopt("socket", "rcvtimeo", socket_timeout)
  sock:setopt("tcp", "nodelay", 1)

  sock:write(params)
  sock:writeall("\r\n")

  local response_text = sock:readall()
  sock:close()

  send_response(response_text, jsonp_callback)
end

function build_bridge_mailbox_request()
  local method = luci.http.getenv("REQUEST_METHOD")
  local jsonp_callback = extract_jsonp_param(luci.http.getenv("QUERY_STRING"))
  local parts = parts_after("mailbox")
  local params = {}
  for idx, param in ipairs(parts) do
    if not_nil_or_empty(param) then
      table.insert(params, param)
    end
  end

  if #params == 0 then
    luci.http.status(400)
    return
  end

  local bridge_request = build_bridge_request("raw", params)
  if not bridge_request then
    luci.http.status(403)
    return
  end

  local uci = luci.model.uci.cursor()
  uci:load("domino")
  local socket_timeout = uci:get_first("domino", "domino", "socket_timeout", 5)

  local sock, code, msg = nixio.connect("127.0.0.1", 5700)
  if not sock then
    code = code or ""
    msg = msg or ""
    http_error(500, "nil socket, " .. code .. " " .. msg)
    return
  end

  sock:setopt("socket", "sndtimeo", socket_timeout)
  sock:setopt("socket", "rcvtimeo", socket_timeout)
  sock:setopt("tcp", "nodelay", 1)

  local json = require("luci.json")

  sock:write(json.encode(bridge_request))
  sock:writeall("\n")
  sock:close()

  luci.http.status(200)
end
