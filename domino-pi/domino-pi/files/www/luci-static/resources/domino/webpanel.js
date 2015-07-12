"use strict";

/*
 * This file is part of YunWebUI.
 *
 * YunWebUI is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * As a special exception, you may use this file as part of a free software
 * library without restriction.  Specifically, if other files instantiate
 * templates or use macros or inline functions from this file, or you compile
 * this file and link it with other files to produce an executable, this
 * file does not by itself cause the resulting executable to be covered by
 * the GNU General Public License.  This exception does not however
 * invalidate any other reasons why the executable file might be covered by
 * the GNU General Public License.
 *
 * Copyright 2013 Arduino LLC (http://www.arduino.cc/)
 */

$.fn.serializeObject = function()
{
    var o = {};
    var a = this.serializeArray();
    $.each(a, function() {
        if (o[this.name] !== undefined) {
            if (!o[this.name].push) {
                o[this.name] = [o[this.name]];
            }
            o[this.name].push(this.value || '');
        } else {
            o[this.name] = this.value || '';
        }
    });
    return o;
};

function ap_encryption_changed(form){
    var ap_encryption = form["ap_encryption"];
	var ap_password = form["ap_password"];
	if(ap_encryption.value=="none"){
	    ap_password.placeholder="";
	}else if(ap_encryption.value=="wep"){
	    ap_password.placeholder="Length should be 5 or 13 characters";
	}else{
	    ap_password.placeholder="Minimum 8 characters";
	}
}

function networkCheck(form) {
	var wan_protocol=form["wan_protocol"].value;
	
	var ipaddr=form["ipaddr"];
	var netmask=form["netmask"];
	var gateway=form["gateway"];
	var dns=form["dns"];

	var ap_enable=form["ap_enable"];
	var ap_ssid = form["ap_ssid"];
	var ap_encryption = form["ap_encryption"];
	var ap_password = form["ap_password"];
	
	var username=form["username"];
	var password=form["password"];
	var modem=form["modem"];
	var apn=form["apn"];
	var pin=form["pin"];
	var phone=form["phone"];
	
	var errors;

	var errContainer = document.getElementById("error_response");

	errContainer.innerHTML = "";
	errors = false;

	username.className = "normal";
	password.className = "normal";
	ipaddr.className = "normal";
	netmask.className = "normal";
	gateway.className = "normal";
	dns.className = "normal";
	ap_password.className = "normal";
	ap_ssid.className = "normal";
	errContainer.className = "hidden";
	

	function nullOrEmpty(val) {
		return val == null || val === "";
	}
	
	if(wan_protocol=="dhcp"){
		
	}else if(wan_protocol=="static"){
		if(nullOrEmpty(ipaddr.value)){
			errorHandler(ipaddr, errContainer, "IP Address should be xxx.xxx.xxx.xxx");
			errors=true;
		}
		if(nullOrEmpty(netmask.value)){
			errorHandler(netmask, errContainer, "Netamsk should be 255.255.255.0 etc.");
			errors=true;
		}
		if(nullOrEmpty(gateway.value)){
			errorHandler(gateway, errContainer, "Gateway should be xxx.xxx.xxx.xxx");
			errors=true;
		}
	}else if(wan_protocol=="pppoe"){
		if(nullOrEmpty(username.value)){
			errorHandler(username, errContainer, "Please type your username");
			errors=true;
		}
	}else if(wan_protocol=="3g"){
		if($("#modem").val()=="0"){
			errorHandler(phone, errContainer, "Please choose a valid device");
			errors=true;
		}
		if(nullOrEmpty(apn.value)){
			errorHandler(apn, errContainer, "Please type your apn");
			errors=true;
		}
	}else if(wan_protocol=="usb"){
		if($("#phone").val()=="0"){
			errorHandler(phone, errContainer, "Please choose a valid device");
			errors=true;
		}
	}else if(wan_protocol=="wifi"){
	  if (!wifi_ssid.disabled && nullOrEmpty(wifi_ssid.value)) {
		errorHandler(wifi_ssid, errContainer, "Please choose a WiFi network name");
		errors = true;
	  }

	  if (!wifi_password.disabled && wifi_encryption.value != "none") {
		if (nullOrEmpty(wifi_password.value)) {
			
		}else if(wifi_encryption.value == "wep" && ap_password.value.length != 13 && ap_password.value.length !=5){
			errorHandler(wifi_password, errContainer, "WiFi password must be 5 or 13 characters");
			errors = true;
		}
		else if (wifi_encryption.value != "wep" && wifi_password.value.length < 8) {
		  errorHandler(wifi_password, errContainer, "WiFi password must be at least 8 characters");
		  errors = true;
		}
	  }
	}
	
	if(ap_enable.checked){
		if(nullOrEmpty(ap_ssid.value)){
			errorHandler(ap_ssid, errContainer, "SSID required");
			errors = true;
		}
		if(ap_encryption.value=="wep" && ap_password.placeholder != "Keep Unchanged"){
			if(ap_password.value.length != 13 && ap_password.value.length !=5){
				errorHandler(ap_password, errContainer, "WiFi password must be 5 or 13 characters");
				errors = true;
			}
		}else if(ap_encryption.value !="none" && ap_password.placeholder != "Keep Unchanged"){
			if(ap_password.value.length <8 && ap_password.value !=""){
				errorHandler(ap_password, errContainer, "WiFi password must be at least 8 characters");
				errors = true;
			}
		}
	}

  return !errors;
}

 
function formCheck(form) {
  var wifi_ssid = form["wifi.ssid"];
  var wifi_encryption = form["wifi.encryption"];
  var wifi_password = form["wifi.password"];
  var hostname = form["hostname"];
  var password = form["password"];
  var errors;

  var errContainer = document.getElementById("error_response");

  errContainer.innerHTML = "";
  errors = false;

  wifi_password.className = "normal";
  wifi_ssid.className = "normal";
  hostname.className = "normal";
  password.className = "normal";
  errContainer.className = "hidden";

  function nullOrEmpty(val) {
    return val == null || val === "";
  }

  if (!wifi_ssid.disabled && nullOrEmpty(wifi_ssid.value)) {
    errorHandler(wifi_ssid, errContainer, "Please choose a WiFi network name");
    errors = true;
  }

  if (!wifi_password.disabled && wifi_encryption.value != "none") {
    if (nullOrEmpty(wifi_password.value)) {
      errorHandler(wifi_password, errContainer, "Please choose a WiFi password");
      errors = true;
    } else if (wifi_encryption.value != "wep" && wifi_password.value.length < 8) {
      errorHandler(wifi_password, errContainer, "WiFi password should be 8 char at least");
      errors = true;
    }
  }

  if (nullOrEmpty(hostname.value)) {
    errorHandler(hostname, errContainer, "Please choose a name for your Y&uacute;n");
    errors = true;

  } else if (hostname.value.match(/[^a-zA-Z0-9]/)) {
    errorHandler(hostname, errContainer, "You can only use alphabetical characters for the hostname (A-Z or a-z)");
    errors = true;
  }

  if (password.value != null && password.value != "" && password.value.length < 8) {
    errorHandler(password, errContainer, "Password should be 8 char at least");
    errors = true;
  } else if (!passwords_match()) {
    errorHandler(password, errContainer, "Passwords do not match");
    errors = true;
  }

  return !errors;
}

function basicCheck(form) {
  var hostname = form["hostname"];
  var password = form["password"];
  var errors;
  var errContainer = document.getElementById("error_response");
  errContainer.innerHTML = "";
  errors = false;

  hostname.className = "normal";
  password.className = "normal";
  errContainer.className = "hidden";

  function nullOrEmpty(val) {
    return val == null || val === "";
  }

  if (nullOrEmpty(hostname.value)) {
    errorHandler(hostname, errContainer, "Please choose a name for your Domino");
    errors = true;

  } else if (hostname.value.match(/[^a-zA-Z0-9]/)) {
    errorHandler(hostname, errContainer, "You can only use alphabetical characters for the hostname (A-Z or a-z)");
    errors = true;
  }

  if (nullOrEmpty(password.value) || password.value.length < 8) {
    errorHandler(password, errContainer, "Password should be 8 char at least");
    errors = true;
  } else if (!passwords_match()) {
    errorHandler(password, errContainer, "Passwords do not match");
    errors = true;
  }
  return !errors;
}

function formReset() {
  setTimeout(function() {
    grey_out_wifi_conf(!document.getElementById("wificheck").checked);
    onchange_security(document.getElementById("wifi_encryption"));
  }, 100);
}

function errorHandler(el, er, msg) {
  el.className = "error";
  er.className = "visible";
  er.innerHTML = "<p>" + er.innerHTML + msg + "<br /></p>";
}

function goto(href) {
  document.location = href;
  return false;
}

function onchange_security(select) {
  var wifi_pass_container = document.getElementById("wifi_password_container");
  var wifi_pass = document.getElementById("wifi_password");
  if (select.value == "none") {
    wifi_pass_container.setAttribute("class", "hidden");
  } else {
    wifi_pass_container.removeAttribute("class");
    wifi_pass.value = "";
    wifi_pass.focus();
  }
}

var pu, key_id, public_key;
if (typeof(getPublicKey) === "function") {
  pu = new getPublicKey(pub_key);
  key_id = pu.keyid;
  public_key = pu.pkey.replace(/\n/g, "");
}

function send_post(url, form, real_form_id) {
  var json=$(form).serializeObject();
  var pgp_message = doEncrypt(key_id, 0, public_key, JSON.stringify(json));
  var real_form = document.getElementById(real_form_id);
  real_form.pgp_message.value = pgp_message;
  real_form.submit();
  return false;
}

function grey_out_wifi_conf(disabled) {
  if (disabled) {
    document.getElementById("wifi_container").setAttribute("class", "disabled");
  } else {
    document.getElementById("wifi_container").setAttribute("class", "");
  }
  document.getElementById("wifi_password").disabled = disabled;
  document.getElementById("wifi_ssid").disabled = disabled;
  document.getElementById("wifi_encryption").disabled = disabled;
  document.getElementById("detected_wifis").disabled = disabled;
}

function grey_out_ap(disabled) {
  if (disabled) {
    document.getElementById("ap_container").setAttribute("class", "disabled");
  } else {
    document.getElementById("ap_container").setAttribute("class", "");
  }
  document.getElementById("ap_password").disabled = disabled;
  document.getElementById("ap_ssid").disabled = disabled;
  document.getElementById("ap_encryption").disabled = disabled;
}

function passwords_match() {
  var confpassword = document.getElementById("confpassword");
  var password = document.getElementById("password");
  return confpassword.value == password.value;
}

function show_message_is_passwords_dont_match() {
  if (passwords_match()) {
    document.getElementById("pass_mismatch").setAttribute("class", "hidden error_container input_message");
  } else {
    document.getElementById("pass_mismatch").setAttribute("class", "error_container input_message");
  }
}

function fileSelected(){
	$("#progress_bar_upload").show();
	//var file = document.getElementById("firmware").files[0];
	var form = document.getElementById("form_firmware");
	//if(file){
		var xhr=new XMLHttpRequest();
		//var fd=document.getElementById("form_firmware").getFormData();
		var fd = new FormData(form);
		xhr.upload.addEventListener("progress",uploadProgress,false);
		xhr.addEventListener("load", uploadComplete, false);
		xhr.addEventListener("error", uploadFailed, false);
		xhr.addEventListener("abort", uploadCanceled, false);
		xhr.open("POST",form.getAttribute('action'),true);
		xhr.send(fd);
	//}
  }
function uploadProgress(evt) {
  if (evt.lengthComputable) {
	var percentComplete = Math.round(evt.loaded * 100 / evt.total);
	var percent_text=percentComplete.toString() +"%";
	$("#progress_bar_upload span").width(percent_text);
	$("#progress_bar_upload span").text(percent_text);
  }
  else {
	//document.getElementById('progressNumber').innerHTML = 'unable to compute';
  }
}

function uploadComplete(evt) {
  /* This event is raised when the server send back a response */
	$("#upload_info").show();
	var json = JSON.parse(evt.target.responseText);
	if(json.supported){
		$("#upload_info").html("<b>Firmware ready. You can upgrade now!</b>");
		$("#upgrade_bar").show();
	}else{
		$("#upload_info").html("<font color='red'>This firmware is not supported!</font>");
	}
}

function uploadFailed(evt) {
	$("#upload_info").show();
	$("#upload_info").text("There was an error attempting to upload the file");
}

function uploadCanceled(evt) {
	$("#upload_info").show();
	$("#upload_info").text("The upload has been canceled by the user or the browser dropped the connection.");
}  

function onclick_upgrade() {
  $("#progress_bar_upload").attr("style", "visibility:visible");
  $("#upload_button").addClass("btn").attr("disabled", "true");
}
function check_firmware_online(){
	$.getJSON(check_url,function (data){
		$("#firmware_new").val(data.version);
		if(data.new){
			$("#download_firmware").show();
		}
	});
}
var download_process;
var download_check=0;
function update_download_progress(){
	$.getJSON(downloading_url +"?check="+download_check,function(data){
		//$("#firmware_new").val(data.percent);
		var percentComplete = Math.round(data.percent*100);
		var percent_text=percentComplete.toString() +"%";
		$("#progress_bar_upload span").width(percent_text);
		$("#progress_bar_upload span").text(percent_text);
		if(!data.done){
			setTimeout(update_download_progress,1000);
		}else{
			$("#upload_info").show();
			if(data.supported){
				$("#upload_info").html("<b>Firmware ready. You can upgrade now!</b>");
				$("#upgrade_bar").show();
			}else{
				$("#upload_info").html("<font color='red'>This firmware is not supported!</font>");
			}
		}
		download_check = download_check+1;
	});
}
function download_firmware(){
	download_check=0;
	$("#progress_bar_upload").show();
	update_download_progress();
}
document.body.onload = function() {
  if ($("#progress_bar_upload").length > 0) {
    $("#upload_button").click(onclick_upgrade);
  }
  var firmware_new = document.getElementById("firmware_new");
  
  if (firmware_new){
	  check_firmware_online();
  }

  if (document.getElementById("username")) {
    document.getElementById("password").focus();
  }
  var wificheck = document.getElementById("wificheck");
  if (wificheck) {
    wificheck.onclick = function(event) {
      grey_out_wifi_conf(!event.target.checked);
    }
  }
  
  var ap_enable = document.getElementById("ap_enable");
  if (ap_enable) {
    ap_enable.onclick = function(event) {
      grey_out_ap(!event.target.checked);
    }
  }
  
  var wifi_encryption = document.getElementById("wifi_encryption");
  if (wifi_encryption) {
    wifi_encryption.onchange = function(event) {
      onchange_security(event.target);
    }
  }
  var confpassword = document.getElementById("confpassword");
  if (confpassword) {
    confpassword.onkeyup = show_message_is_passwords_dont_match;
    document.getElementById("password").onkeyup = show_message_is_passwords_dont_match;
  }

  var dmesg = document.getElementById("dmesg");
  if (dmesg) {
    $("#dmesg").hide();
    $("#dmesg_toogle").on("click", function() {
      if ($(this).text() == "Show") {
        $("#dmesg").show();
        $(this).text("Hide");
      } else {
        $("#dmesg").hide();
        $(this).text("Show");
      }
      return false;
    });
  }

  var detected_wifis = document.getElementById("detected_wifis");
  if (detected_wifis) {
    var detect_wifi_networks = function() {
      var detected_wifis = $("#detected_wifis");
      if (detected_wifis[0].disabled) {
        return false;
      }
      detected_wifis.empty();
      detected_wifis.append("<option>Detecting ...</option>");
      $.get(refresh_wifi_url, function(wifis) {
        detected_wifis.empty();
        detected_wifis.append("<option>Select a wifi network...</option>");
        for (var idx = 0; idx < wifis.length; idx++) {
          var html = "<option value=\"" + wifis[idx].name + "|||" + wifis[idx].encryption + "\">" + wifis[idx].name + " (";
          if (wifis[idx].encryption !== "none") {
            html = html + wifis[idx].pretty_encryption + ", ";
          }
          html = html + "quality " + wifis[idx].signal_strength + "%";
          html = html + ")</option>";
          detected_wifis.append(html);
        }
      });
      return false;
    };
    document.getElementById("refresh_detected_wifis").onclick = detect_wifi_networks;

    detected_wifis.onchange = function() {
      var parts = $("#detected_wifis").val().split("|||");
      if (parts.length !== 2) {
        return;
      }
      $("#wifi_ssid").val(parts[0]);
      var $wifi_encryption = $("#wifi_encryption");
      $wifi_encryption.val(parts[1]);
      $wifi_encryption.change();
    };
    
    $("#wan_protocol").change(function(){
		var protocol=$("#wan_protocol").val();
		$("#username").parent().parent().hide();
		$("#password").parent().parent().hide();
		$("#ipaddr").parent().parent().hide();
		$("#netmask").parent().parent().hide();
		$("#gateway").parent().parent().hide();
		$("#dns").parent().parent().hide();
		$("#modem").parent().parent().hide();
		$("#service").parent().parent().hide();
		$("#apn").parent().parent().hide();
		$("#pin").parent().parent().hide();
		$("#phone").parent().parent().hide();
		$("#wifi_container").hide();
		if (protocol=="dhcp"){

		}else if (protocol=="static"){
			$("#ipaddr").parent().parent().show();
			$("#netmask").parent().parent().show();
			$("#gateway").parent().parent().show();
			$("#dns").parent().parent().show();
		}else if (protocol=="pppoe"){
			$("#username").parent().parent().show();
			$("#password").parent().parent().show();
		}else if (protocol=="3g"){
			$("#modem").parent().parent().show();
			$("#service").parent().parent().show();
			$("#apn").parent().parent().show();
			$("#pin").parent().parent().show();
			$("#username").parent().parent().show();
			$("#password").parent().parent().show();
			
		}else if (protocol=="usb"){
			$("#phone").parent().parent().show();
		}else if (protocol=="wifi"){
			$("#wifi_container").show();
		}
	});
    detect_wifi_networks();
  }

  var restopen = document.getElementById("restopen");
  if (restopen) {
    var toogle_rest_api = function() {
      var data = {};
      data[this.name] = $(this).val();
      $.post(this.form.action, data);
    };
    restopen.onclick = toogle_rest_api;
    document.getElementById("restpass").onclick = toogle_rest_api;
  }
};
