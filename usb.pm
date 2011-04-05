use strict;

sub usb_init {
    #initialize hid idle period to 500ms (125*4ms)
    _ldi r16, 125;
    _sts hid_idle_period, r16;

    #enable usb pad regulator and select usb device mode
    _ldi r16, MASK(UIMOD) | MASK(UVREGE);
    _sts UHWCON, r16;

    #enable USB module, with clock frozen
    _ldi r16, MASK(USBE) | MASK(FRZCLK);
    _sts USBCON, r16;

    #set USB PLL prescalar value
    _ldi r16, PLL_8 | MASK(PLLE);
    _sts PLLCSR, r16;

    block {
        _lds r16, PLLCSR;
        _bst r16, PLOCK;
        _brtc begin_label;
    };

    #enable VBUS pad
    _ldi r16, MASK(USBE) | MASK(OTGPADE);
    _sts USBCON, r16;

    #attach usb
    _ldi r16, 0;
    _sts UDCON, r16;

    #enable end of reset interrupt
    _ldi r16, MASK(EORSTE);
    _sts UDIEN, r16;
}

sub USB_WAIT_FOR_TXINI {
    my($tempreg) = shift;

    block {
        _lds $tempreg, UEINTX;
        _sbrs $tempreg, TXINI;
        _rjmp begin_label;
    };
}

sub USB_SEND_QUEUED_DATA {
    my($tempreg) = shift;

    _lds $tempreg, UEINTX;
    _cbr $tempreg, MASK(TXINI);
    _sts UEINTX, $tempreg;
}

sub USB_SEND_ZLP {
    my($tempreg) = shift;

    USB_WAIT_FOR_TXINI $tempreg;
    _cbr $tempreg, MASK(TXINI);
    _sts UEINTX, $tempreg;
}

emit_global_sub "usb_gen", sub {
    #check for End of Reset interrupt
    _lds r16, UDINT;
    _sbrc r16, EORSTI;
    _call "eor_int";

    #clear USB device interrupts
    _ldi r16, 0;
    _sts UDINT, r16;

    _reti;
};

#this interrupt occurs when the usb controller has finished reseting, and is ready to be used
emit_sub "eor_int", sub {
    SELECT_EP r16, EP_0;

    #enable ep0
    _ldi r16, MASK(EPEN);
    _sts UECONX, r16;

    #configure ep0
    _ldi r16, EPTYPE_CONTROL | EPDIR_OUT;
    _sts UECFG0X, r16;

    _ldi r16, EPSIZE_64 | EPBANK_SINGLE | MASK(ALLOC);
    _sts UECFG1X, r16;

    #enable setup packet interrupt
    _ldi r16, MASK(RXSTPE);
    _sts UEIENX, r16;

    _ret;
};

{
    my($r10_max_packet_length) = "r10";

    emit_global_sub "usb_enp", sub {
        #check for endpoints with interrupts
        _lds r0, UEINT;

        #check EP0
        block {
            _sbrs r0, EPINT0;
            _rjmp end_label;

            SELECT_EP r16, EP_0;

            #setup max_packet_length shared register
            _ldi r16, 0x40;
            _mov $r10_max_packet_length, r16;

            _call "handle_setup_packet";
        };

        _reti;

        emit_sub "handle_setup_packet", sub {
            #check if we got an interrupt for a setup packet
            _lds r24, UEINTX;
            _sbrs r24, RXSTPI;
                _ret;

            #setup some local register aliases, for clarity
            my($r16_bmRequestType) = "r16";
            my($r17_bRequest) = "r17";
            my($r18_wValue_lo) = "r18";
            my($r19_wValue_hi) = "r19";
            my($r20_wIndex_lo) = "r20";
            my($r21_wIndex_hi) = "r21";
            my($r22_wLength_lo) = "r22";
            my($r23_wLength_hi) = "r23";

            #read in the setup packet
            _lds $r16_bmRequestType, UEDATX;
            _lds $r17_bRequest, UEDATX;
            _lds $r18_wValue_lo, UEDATX;
            _lds $r19_wValue_hi, UEDATX;
            _lds $r20_wIndex_lo, UEDATX;
            _lds $r21_wIndex_hi, UEDATX;
            _lds $r22_wLength_lo, UEDATX;
            _lds $r23_wLength_hi, UEDATX;

            #clear the setup interrupt bit
            _cbr r24, MASK(RXSTPI);
            _sts UEINTX, r24;

            #is it a class request?
            _sbrc $r16_bmRequestType, 5;
            _rjmp "handle_hid_packet";

            #is it a vendor request?
            _sbrc $r16_bmRequestType, 6;
            _rjmp "setup_unknown";

            jump_table(value=>$r17_bRequest, initial_index=>0, invalid_value_label=>"setup_unknown", table=>[
                "setup_get_status",         #0x00
                "setup_clear_feature",      #0x01
                "setup_unknown",            #0x02
                "setup_set_feature",        #0x03
                "setup_unknown",            #0x04
                "setup_set_address",        #0x05
                "setup_get_descriptor",     #0x06
                "setup_set_descriptor",     #0x07
                "setup_get_configuration",  #0x08
                "setup_set_configuration",  #0x09
                "setup_get_interface",      #0x0a
                "setup_set_interface",      #0x0b
                "setup_synch_frame"         #0x0c
            ]);


            emit_sub "setup_unknown", sub {
                _ret;
            };

            emit_sub "handle_hid_packet", sub {
                _ret;
            };

            emit_sub "setup_get_status", sub {
                _ret;
            };

            emit_sub "setup_clear_feature", sub {
                _ret;
            };

            emit_sub "setup_set_feature", sub {
                _ret;
            };

            emit_sub "setup_set_address", sub {
                _ret;
            };

            emit_sub "setup_get_descriptor", sub {
                #check for normal descriptor request
                block {
                    _cpi $r16_bmRequestType, 0b10000000;
                    _brne end_label;

                    jump_table(value=>$r19_wValue_hi, initial_index=>0, invalid_value_label=>"setup_get_descriptor_end", table=>[
                        "setup_get_descriptor_end",                         #0x00
                        "setup_get_device_descriptor",                      #0x01
                        "setup_get_configuration_descriptor",               #0x02
                        "setup_get_string_descriptor",                      #0x03
                        "setup_get_interface_descriptor",                   #0x04
                        "setup_get_endpoint_descriptor",                    #0x05
                        "setup_get_device_qualifier_descriptor",            #0x06
                        "setup_get_other_speed_configuration_descriptor",   #0x07
                        "setup_get_interface_power_descriptor"              #0x08
                    ]);
                };

                #check for HID class descriptor request
                #_cpi $r16_bmRequestType, 0b10000001;
                #forward_branch \&_brne, sub {
                #};

                #otherwise, unsupported
                emit "setup_get_descriptor_end:\n";
                indent_block {
                    _ret;
                };

                emit_sub "setup_get_device_descriptor", sub {
                    #if more than 255 bytes are requested, round down to 255
                    #(i.e. set the low byte to 255 - the high byte is otherwise ignored)
                    _cpse $r23_wLength_hi, r15_zero;
                    _ldi $r22_wLength_lo, 0xff;

                    #TODO: do we need to send a zlp if 0 bytes are requested?
                    _cpi $r22_wLength_lo, 0;
                    _breq "setup_get_descriptor_end";

                    _ldi zl, lo8("DEVICE_DESCRIPTOR");
                    _ldi zh, hi8("DEVICE_DESCRIPTOR");

                    #check if the requested number of bytes is less than the descriptor length
                    block {
                        _cpi $r22_wLength_lo, 0x12;
                        _brlo end_label;
                        _ldi $r22_wLength_lo, 0x12;
                    };

                    _rjmp "usb_send_data_short"; #tail call
                };

                emit_sub "setup_get_configuration_descriptor", sub {
                    _ret;
                };

                emit_sub "setup_get_string_descriptor", sub {
                    _ret;
                };

                emit_sub "setup_get_interface_descriptor", sub {
                    _ret;
                };

                emit_sub "setup_get_endpoint_descriptor", sub {
                    _ret;
                };

                emit_sub "setup_get_device_qualifier_descriptor", sub {
                    _ret;
                };

                emit_sub "setup_get_other_speed_configuration_descriptor", sub {
                    _ret;
                };

                emit_sub "setup_get_interface_power_descriptor", sub {
                    _ret;
                };
            };

            emit_sub "setup_set_descriptor", sub {
                _ret;
            };

            emit_sub "setup_get_configuration", sub {
                _ret;
            };

            emit_sub "setup_set_configuration", sub {
                _ret;
            };

            emit_sub "setup_get_interface", sub {
                _ret;
            };

            emit_sub "setup_set_interface", sub {
                _ret;
            };

            emit_sub "setup_synch_frame", sub {
                _ret;
            };
        };
    };

    #Sends up to 255 bytes to the currently selected usb endpoint
    #zh:zl should point to the data to send
    #r22 should contain the amount of data to send
    #r10 should contain the maximum packet length for this endpoint
    #r22, r23 and r24 will be clobbered on exit
    emit_sub "usb_send_data_short", sub {
        my($r22_data_len) = "r22";
        my($r23_current_packet_len) = "r23";
        my($r24_temp_reg) = "r24";

        block {
            #load the size of the next packet into r23
            _mov $r23_current_packet_len, $r10_max_packet_length;

            #if data_len <= current_packet_len
            block {
                _cp $r23_current_packet_len, $r22_data_len;
                _brlo end_label;

                _mov $r23_current_packet_len, $r22_data_len;
            };

            #txini must be set before we queue any data
            USB_WAIT_FOR_TXINI r24;

            #queue the data for the next packet
            block {
                _lpm $r24_temp_reg, "z+";
                _sts UEDATX, $r24_temp_reg;
                _dec r23;
                _brne begin_label;
            };

            #send the data
            USB_SEND_QUEUED_DATA $r24_temp_reg;

            _sub $r22_data_len, $r10_max_packet_length;

            #if z is set, we are done sending data, and need to send a zlp
            #if c is set, we are done sending data, and don't need to send a zlp
            #if neither of the above, we have more data to send

            _brbs BIT_C, end_label;
            _brbc BIT_Z, begin_label;
            USB_SEND_ZLP r24;
        };

        _ret;
    };
}