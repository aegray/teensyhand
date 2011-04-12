#!/usr/bin/perl
use strict;

BEGIN {
    do "AVR.pm";
    die $@ if ($@);
}

BEGIN {
    emit ".section .bss\n";

    #make the button event queue be 256 byte aligned, so we can easily use mod 256 arithmetic
    #we should already be aligned since this should be the beginning of the .bss section, so
    #this is mostly informational
    emit ".align 8\n";

    #a queue to hold the button press and release events generated by logic associated with timer3
    #The lower 6 bits of each item hold the button index, while the MSB indicates if it was a
    #press (1) or release (0) event
    #We shouldn't near this much space, but it makes the math much cheaper
    #since we get mod 256 arithmetic "for free"
    memory_variable "button_event_queue", 0x100;

    #The head and tail of the button queue
    memory_variable "button_event_head", 1;
    memory_variable "button_event_tail", 1;

    #done in begin section, so that declared constants can be accessed further down
    memory_variable "current_configuration";
    memory_variable "hid_idle_period";

    #contains the button states for each selector value
    #the button states are stored in the low nibble of each byte.
    #The high nibbles are not used
    memory_variable "button_states", 13;

    #contains the current state of the hid report
    memory_variable "current_report", 21;

    #the MSB is a flag that indicates whether the actual, physical shift button is pressed
    #The lower 7 bits contain a count of the "shifted" keys that are pressed
    memory_variable "lshift_status", 1;

    #The address of the press table for the current keyboard mode
    memory_variable "current_press_table", 2;

    #The address of the press table for the "persistent" mode - that is, the mode that we go back
    #to after a temporary mode switch (i.e. the nas button)
    memory_variable "persistent_mode_press_table", 2;

    #This contains a 2-byte entry for each button, which is the address of a routine to
    #execute when the button is released. The entry for a button is updated when the button
    #is pressed, to reflect the correct routine to use when it is released
    #In this way, we can correctly handle button releases when the mode changes while a
    #button is pressed
    memory_variable "release_table", 104;



    emit ".text\n";
}

use constant BUTTON_RELEASE => 0;
use constant BUTTON_PRESS => 1;

use constant BIT_LCTRL => 0;
use constant BIT_LSHIFT => 1;
use constant BIT_LALT => 2;
use constant BIT_LGUI => 3;
use constant BIT_RCTRL => 4;
use constant BIT_RSHIFT => 5;
use constant BIT_RALT => 6;
use constant BIT_RGUI => 7;

do "descriptors.pm";
die $@ if ($@);

do "usb.pm";
die $@ if ($@);

do "timer.pm";
die $@ if ($@);

sub dequeue_input_event;
sub process_input_event;

emit_global_sub "main", sub {
    SET_CLOCK_SPEED r16, CLOCK_DIV_1;

    CONFIGURE_GPIO(port=>GPIO_PORT_A, pin=>PIN_0, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_A, pin=>PIN_1, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_A, pin=>PIN_2, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_A, pin=>PIN_3, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_A, pin=>PIN_4, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_A, pin=>PIN_5, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_A, pin=>PIN_6, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_A, pin=>PIN_7, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);

    CONFIGURE_GPIO(port=>GPIO_PORT_B, pin=>PIN_0, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_B, pin=>PIN_1, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_B, pin=>PIN_2, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_B, pin=>PIN_3, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_B, pin=>PIN_4, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_B, pin=>PIN_5, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_B, pin=>PIN_6, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_B, pin=>PIN_7, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);

    CONFIGURE_GPIO(port=>GPIO_PORT_C, pin=>PIN_0, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_C, pin=>PIN_1, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_C, pin=>PIN_2, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_C, pin=>PIN_3, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_C, pin=>PIN_4, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_C, pin=>PIN_5, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_C, pin=>PIN_6, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_C, pin=>PIN_7, dir=>GPIO_DIR_OUT);

    CONFIGURE_GPIO(port=>GPIO_PORT_D, pin=>PIN_0, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_D, pin=>PIN_1, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_D, pin=>PIN_2, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_D, pin=>PIN_3, dir=>GPIO_DIR_OUT);
    CONFIGURE_GPIO(port=>GPIO_PORT_D, pin=>PIN_4, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_D, pin=>PIN_5, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_D, pin=>PIN_6, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_D, pin=>PIN_7, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);

    CONFIGURE_GPIO(port=>GPIO_PORT_E, pin=>PIN_0, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_E, pin=>PIN_1, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_E, pin=>PIN_2, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_E, pin=>PIN_3, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_E, pin=>PIN_4, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_E, pin=>PIN_5, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_E, pin=>PIN_6, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_E, pin=>PIN_7, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);

    CONFIGURE_GPIO(port=>GPIO_PORT_F, pin=>PIN_0, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_F, pin=>PIN_1, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_F, pin=>PIN_2, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_F, pin=>PIN_3, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_F, pin=>PIN_4, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_F, pin=>PIN_5, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_F, pin=>PIN_6, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);
    CONFIGURE_GPIO(port=>GPIO_PORT_F, pin=>PIN_7, dir=>GPIO_DIR_IN, pullup=>GPIO_PULLUP_ENABLED);

    #initialize register with commonly used "zero" value
    _clr r15_zero;

    _ldi zl, 0x00;
    _ldi zh, 0x01;

    #reset all memory to 0s
    block {
        _st "z+", r15_zero;

        _cpi zl, 0x00;
        _brne begin_label;

        _cpi zh, 0x21;
        _brne begin_label;
    };

    usb_init();

    #timer1_init();

    timer3_init();
    enable_timer3(r16);

    #enable interrupts
    _sei;

    #initialize the press tables
    _ldi r16, lo8("press_table_0");
    _sts current_press_table, r16;
    _sts persistent_mode_press_table, r16;

    _ldi r16, hi8("press_table_0");
    _sts "current_press_table + 1", r16;
    _sts "persistent_mode_press_table + 1", r16;

    block {
        #wait for an input event and dequeue it
        dequeue_input_event;
        #generate and send the hid report(s)
        process_input_event;

        #and do it all over again
        _rjmp begin_label;
    };
};

#Waits for an input event and dequeues it into the given register
sub dequeue_input_event {
    _ldi yh, hi8(button_event_queue);
    block {
        _cli;

        _lds yl, button_event_head;
        _lds r16, button_event_tail;

        block {
            _cp yl, r16;
            _breq end_label;

            _ld r16, "y+";
            _sts button_event_head, yl;
            _sei;
            _rjmp end_label parent;
        };

        _sei;
        _rjmp begin_label;
    };
}

sub process_input_event {
    block {
        #we've got the input event in r16

        #extract the button index and store it in r17
        _mov r17, r16;
        _cbr r17, 0x80;
        #we really only need index*2 for address offsets/lookups (which are 2 bytes each)
        _lsl r17;

        block {
            block {
                #is it a press or release?
                _sbrc r16, 7;
                _rjmp end_label;

                #it's a release event. Load the handler address from the release table
                _ldi zl, lo8(release_table);
                _ldi zh, hi8(release_table);
                _add zl, r17;
                _adc zh, r15_zero;
                _ld r18, "z+";
                _ld r19, "z";
                _movw zl, r18;

                _rjmp end_label parent;
            };

            #it's a press event. Load the address for the current press table
            _lds zl, current_press_table;
            _lds zh, "current_press_table+1";

            #lookup the handler address from the table
            _add zl, r17;
            _adc zh, r15_zero;
            _lpm r16, "z+";
            _lpm r17, "z";
            _movw zl, r16;
        };

        _icall;
    };
}

#maps a button index to it's corresponding finger+direction
my(@index_map) = (
    #selector 0x00
    ["r1", "west"],             #0x00
    ["r1", "north"],            #0x01
    ["l4", "west"],             #0x02
    ["l4", "north"],            #0x03

    #selector 0x01
    ["r1", "down"],             #0x04
    ["r1", "east"],             #0x05
    ["l4", "down"],             #0x06
    ["l4", "east"],             #0x07

    #selector 0x02
    ["r1", "south"],            #0x08
    ["r2", "south"],            #0x09
    ["l4", "south"],            #0x0a
    ["l3", "south"],            #0x0b

    #selector 0x03
    ["r2", "west"],             #0x0c
    ["r2", "north"],            #0x0d
    ["l3", "west"],             #0x0e
    ["l3", "north"],            #0x0f

    #selector 0x04
    ["r2", "down"],             #0x10
    ["r2", "east"],             #0x11
    ["l3", "down"],             #0x12
    ["l3", "east"],             #0x13

    #selector 0x05
    ["r3", "west"],             #0x14
    ["r3", "north"],            #0x15
    ["l2", "west"],             #0x16
    ["l2", "north"],            #0x17

    #selector 0x06
    ["r3", "down"],             #0x18
    ["r3", "east"],             #0x19
    ["l2", "down"],             #0x1a
    ["l2", "east"],             #0x1b

    #selector 0x07
    ["r3", "south"],            #0x1c
    ["r4", "south"],            #0x1d
    ["l2", "south"],            #0x1e
    ["l1", "south"],            #0x1f

    #selector 0x08
    ["r4", "west"],             #0x20
    ["r4", "north"],            #0x21
    ["l1", "west"],             #0x22
    ["l1", "north"],            #0x23

    #selector 0x09
    ["r4", "down"],             #0x24
    ["r4", "east"],             #0x25
    ["l1", "down"],             #0x26
    ["l1", "east"],             #0x27

    #selector 0x0a
    ["rt", "lower_outside"],    #0x28
    ["rt", "upper_outside"],    #0x29
    ["lt", "lower_outside"],    #0x2a
    ["lt", "upper_outside"],    #0x2b

    #selector 0x0b
    ["rt", "down"],             #0x2c
    ["rt", "down_down"],        #0x2d
    ["lt", "down"],             #0x2e
    ["lt", "down_down"],        #0x2f

    #selector 0x0c
    ["rt", "inside"],           #0x30
    ["rt", "up"],               #0x31
    ["lt", "inside"],           #0x32
    ["rt", "up"]                #0x33
);

sub finger_map {
    return {
        down=>shift,
        north=>shift,
        east=>shift,
        south=>shift,
        west=>shift
    };
}

sub thumb_map {
    return {
        down => shift,
        down_down => shift,
        up => shift,
        inside => shift,
        lower_outside => shift,
        upper_outside => shift
    }
}

#maps each direction of each finger to a specific action, for normal mode
my(%normal_key_map) = (
    #                 d    n    e    s    w
    r1 => finger_map("h", "g", "'", "m", "d"),
    r2 => finger_map("t", "w", "`", "c", "f"),
    r3 => finger_map("n", "v", undef, "r", "b"),
    r4 => finger_map("s", "z", "\\", "l", ")"),
    #                d      dd         u       in    lo      uo
    rt => thumb_map("nas", "naslock", "func", "sp", "lalt", "bksp"),

    #                 d    n    e    s    w
    l1 => finger_map("u", "q", "i", "p", "\""),
    l2 => finger_map("e", ".", "y", "j", "`"),
    l3 => finger_map("o", ",", "x", "k", "esc"),
    l4 => finger_map("a", "/", "(", ";", "del"),
    #                d         dd          u       in     lo       uo
    lt => thumb_map("lshift", "capslock", "norm", "ret", "lctrl", "tab")
);

my(%nas_key_map) = (
    #                 d    n    e    s    w
    r1 => finger_map("7", "&", undef, "+", "6"),
    r2 => finger_map("8", "*", undef, undef, "^"),
    r3 => finger_map("9", "[", "menu", undef, undef),
    r4 => finger_map("0", "]", undef, undef, "}"),
    #                d      dd         u       in    lo      uo
    rt => thumb_map("nas", "naslock", "func", "sp", "lalt", "bksp"),

    #                 d    n    e    s    w
    l1 => finger_map("4", "\$", "5", "-", undef),
    l2 => finger_map("3", "#", undef, "%", undef),
    l3 => finger_map("2", "@", undef, undef, "esc"),
    l4 => finger_map("1", "!", "{", "=", "del"),
    #                d         dd          u       in     lo       uo
    lt => thumb_map("lshift", "capslock", "norm", "ret", "lctrl", "tab")
);

my(@key_maps) = (
    \%normal_key_map,
    \%nas_key_map
);

#maps an action name to a sub that can generate the press and release code for that action
my(%action_map);
#generate actions for a-z and A-Z
for (my($i)=ord("a"); $i<=ord("z"); $i++) {
    $action_map{chr($i)} = simple_keycode($i - ord("a") + 0x04);
    $action_map{uc(chr($i))} = shifted_keycode($i - ord("a") + 0x04);
}
#generate actions for 1-9
for (my($i)=ord("1"); $i<=ord("9"); $i++) {
    $action_map{chr($i)} = simple_keycode($i - ord("1") + 0x1e);
}
#0 comes before 1 in ascii, but after 9 in usb's keycodes
$action_map{"0"} = simple_keycode(0x27);

$action_map{"!"} = shifted_keycode(0x1e);
$action_map{"@"} = shifted_keycode(0x1f);
$action_map{"#"} = shifted_keycode(0x20);
$action_map{"\$"} = shifted_keycode(0x21);
$action_map{"%"} = shifted_keycode(0x22);
$action_map{"^"} = shifted_keycode(0x23);
$action_map{"&"} = shifted_keycode(0x24);
$action_map{"*"} = shifted_keycode(0x25);
$action_map{"("} = shifted_keycode(0x26);
$action_map{")"} = shifted_keycode(0x27);

$action_map{"ret"} = simple_keycode(0x28);
$action_map{"esc"} = simple_keycode(0x29);
$action_map{"bksp"} = simple_keycode(0x2a);
$action_map{"tab"} = simple_keycode(0x2b);
$action_map{"sp"} = simple_keycode(0x2c);

$action_map{"-"} = simple_keycode(0x2d);
$action_map{"_"} = shifted_keycode(0x2d);
$action_map{"="} = simple_keycode(0x2e);
$action_map{"+"} = shifted_keycode(0x2e);
$action_map{"["} = simple_keycode(0x2f);
$action_map{"{"} = shifted_keycode(0x2f);
$action_map{"]"} = simple_keycode(0x30);
$action_map{"}"} = shifted_keycode(0x30);
$action_map{"\\"} = simple_keycode(0x31);
$action_map{"|"} = shifted_keycode(0x31);
$action_map{";"} = simple_keycode(0x33);
$action_map{":"} = shifted_keycode(0x33);
$action_map{"'"} = simple_keycode(0x34);
$action_map{"\""} = shifted_keycode(0x34);
$action_map{"`"} = simple_keycode(0x35);
$action_map{"~"} = shifted_keycode(0x35);
$action_map{","} = simple_keycode(0x36);
$action_map{"<"} = shifted_keycode(0x36);
$action_map{"."} = simple_keycode(0x37);
$action_map{">"} = shifted_keycode(0x37);
$action_map{"/"} = simple_keycode(0x38);
$action_map{"?"} = shifted_keycode(0x38);

$action_map{"capslock"} = simple_keycode(0x39);

#generate actions for f1-f12
for(my($i)=1; $i<=12; $i++) {
    $action_map{"f$i"} = simple_keycode(0x3A + $i - 1);
}

$action_map{"printscreen"} = simple_keycode(0x46);
$action_map{"scrolllock"} = simple_keycode(0x47);
$action_map{"pause"} = simple_keycode(0x48);
$action_map{"ins"} = simple_keycode(0x49);
$action_map{"home"} = simple_keycode(0x4a);
$action_map{"pgup"} = simple_keycode(0x4b);
$action_map{"del"} = simple_keycode(0x4c);
$action_map{"end"} = simple_keycode(0x4d);
$action_map{"pgdn"} = simple_keycode(0x4e);
$action_map{"right"} = simple_keycode(0x4f);
$action_map{"left"} = simple_keycode(0x50);
$action_map{"down"} = simple_keycode(0x51);
$action_map{"up"} = simple_keycode(0x52);
$action_map{"numlock"} = simple_keycode(0x53);
$action_map{"menu"} = simple_keycode(0x65);

$action_map{"lctrl"} = modifier_keycode(0xe0);
$action_map{"lshift"} = modifier_keycode(0xe1);
$action_map{"lalt"} = modifier_keycode(0xe2);
$action_map{"lgui"} = modifier_keycode(0xe3);
$action_map{"rctrl"} = modifier_keycode(0xe4);
$action_map{"rshift"} = modifier_keycode(0xe5);
$action_map{"ralt"} = modifier_keycode(0xe6);
$action_map{"rgui"} = modifier_keycode(0xe7);

$action_map{"nas"} = nas_action();
$action_map{"naslock"} = undefined_action();
$action_map{"func"} = undefined_action();

for (my($key_map_index)=0; $key_map_index<scalar(@key_maps); $key_map_index++) {
    my($key_map) = $key_maps[$key_map_index];

    #iterate over each physical button, and lookup and emit the code for the
    #press and release actions for each
    my(@press_actions);
    my(@release_actions);
    for (my($i)=0; $i<0x34; $i++) {
        #get the finger+direction combination for this button index
        my($index_map_item) = $index_map[$i];

        my($finger_name) = $index_map_item->[0];
        my($finger_dir) = $index_map_item->[1];

        #get the direction map for a specific finger
        my($finger_map) = $key_map->{$finger_name};

        die "couldn't find map for finger $finger_name" unless (defined($finger_map));

        #get the name of the action associated with this particular button
        my($action_name) = $finger_map->{$finger_dir};
        if (!defined($action_name)) {
            push @press_actions, undef;
            push @release_actions, undef;
            next;
        }

        #now look up the action
        my($action) = $action_map{$action_name};
        if (!defined($action)) {
            die "invalid action - $action_name";
        }

        #this will emit the code for the press and release action
        #and then we save the names in the two arrays, so we can emit a jump table afterwards
        my($actions) = &$action($i);
        push @press_actions, $actions->[BUTTON_PRESS];
        push @release_actions, $actions->[BUTTON_RELEASE];
    }

    #now emit the jump table for normal press actions
    emit_sub "press_table_$key_map_index", sub {
        for (my($i)=0; $i<0x34; $i++) {
            my($action_label) = $press_actions[$i];
            if (defined($action_label)) {
                emit ".word pm($action_label)\n";
            } else {
                emit ".word pm(no_action)\n";
            }
        }
    };

    #now emit the jump table for normal release actions
    emit_sub "release_table_$key_map_index", sub {
        for (my($i)=0; $i<0x34; $i++) {
            my($action_label) = $release_actions[$i];
            if (defined($action_label)) {
                emit ".word pm($action_label)\n";
            } else {
                emit ".word pm(no_action)\n";
            }
        }
    };
}

emit_sub "no_action", sub {
    _ret;
};

#handle the press of a simple (non-shifted) key
#r16 should contain the keycode to send
emit_sub "handle_simple_press", sub {
    #first, we need to check if a virtual lshift is being pressed
    #if so, we need to release the virtual lshift before sending the keycode
    block {
        #check if lshift is pressed in the report
        _lds r17, "current_report + 20";
        _sbrs r17, BIT_LSHIFT;
        _rjmp end_label;

        #if the physical flag is set, the actual physical lshift button is being pressed
        #and we don't want to release it
        _lds r18, lshift_status;
        _sbrc r18, 7;
        _rjmp end_label;

        #it looks like we have a virtual lshift. Clear it and send a report
        _cbr r17, MASK(BIT_LSHIFT);
        _sts "current_report + 20", r17;
        _call "send_hid_report";
    };
    _rjmp "send_keycode_press";
};

#handle the release of a simple (non-shifted) key
#r16 should contain the keycode to release
emit_sub "handle_simple_release", sub {
    _rjmp "send_keycode_release";
};

#adds a keycode to the hid report and sends it
#r16 should contain the keycode to send
emit_sub "send_keycode_press", sub {
    #find the first 0 in current_report, and store the new keycode there
    _ldi zl, lo8(current_report);
    _ldi zh, hi8(current_report);

    _mov r24, zl;
    _adiw r24, 0x20;

    #TODO: we need to handle duplicate keys. e.g. if two buttons are pressed
    #and one is a shifted variant of the other

    block {
        _ld r17, "z+";
        _cp r17, r15_zero;

        block {
            _breq end_label;

            #have we reached the end?
            _cp r24, zl;
            _breq end_label parent;

            _rjmp begin_label parent;
        };

        _st "-z", r16;

        _rjmp "send_hid_report";
    };
    #couldn't find an available slot in the hid report - just return
    #TODO: should report ErrorRollOver in all fields
    _ret;
};

#sends a simple, non-modified key release
#r16 should contain the keycode to release
emit_sub "send_keycode_release", sub {
    #find the keycode in current_report, and zero it out
    _ldi zl, lo8(current_report);
    _ldi zh, hi8(current_report);

    _mov r24, zl;
    _adiw r24, 0x20;

    block {
        _ld r17, "z+";
        _cp r16, r17;

        block {
            _breq end_label;

            #have we reached the end?
            _cp r24, zl;
            _breq end_label parent;

            _rjmp begin_label parent;
        };

        _st "-z", r15_zero;
        _rjmp "send_hid_report";
    };
    #huh? couldn't find the keycode in the hid report. just return
    _ret;
};

#handle a shifted key press
#r16 should contain the keycode to send
emit_sub "handle_shifted_press", sub {
    #increment the virtual count for the lshift key
    _lds r17, lshift_status;
    _inc r17;
    _sts lshift_status, r17;

    block {
        #we need to send a shift press only if it's not already pressed

        #grab the modifier byte from the hid report and check if shift is pressed
        _lds r17, "current_report + 20";
        _sbrc r17, BIT_LSHIFT;
        _rjmp end_label;

        #set the lshift bit
        _sbr r17, MASK(BIT_LSHIFT);
        _sts "current_report + 20", r17;
        _call "send_hid_report";
    };

    _rjmp "send_keycode_press";
};

#handle a shifted key release
#r16 should contain the keycode to release
emit_sub "handle_shifted_release", sub {
    _call "send_keycode_release";

    #decrement the virtual count for the lshift key
    _lds r17, lshift_status;
    _dec r17;
    _sts lshift_status, r17;

    block {
        #we need to send a shift release when lshift is currently present in the
        #hid report and lshift_status is 0 (e.g. both the physical flag and virtual
        #count are 0)

        #first, check if lshift_status is 0 (after we decremented the count)
        _cpi r17, 0;
        _brne end_label;

        #next, check if lshift is present in the hid report
        _lds r17, "current_report + 20";
        _sbrs r17, BIT_LSHIFT;
        _rjmp end_label;

        #clear the lshift bit and send the hid report
        _cbr r17, MASK(BIT_LSHIFT);
        _sts "current_report + 20", r17;
        _rjmp "send_hid_report";
    };

    _ret;
};

#handle a modifier key press
#r16 should contain a mask that specifies which modifier should be sent
#the mask should use the same bit ordering as the modifier byte in the
#hid report
emit_sub "handle_modifier_press", sub {
    #first, check if the modifier key is already pressed
    block {
        #grab the modifier byte from the hid report and check if the modifier is already pressed
        _lds r17, "current_report + 20";
        _cp r18, r17;
        _and r17, r16;
        _brne end_label;

        #set the modifier bit and store it
        _or r18, r16;
        _sts "current_report + 20", r18;

        _rjmp "send_hid_report";
    };
};

#handle a modifier key release
#r16 should contain a mask that specifies which modifier should be sent
#the mask should use the same bit ordering as the modifier byte in the
#hid report
emit_sub "handle_modifier_release", sub {
    #clear the modifier bit and store it
    _lds r17, "current_report + 20";
    _com r16;
    _and r17, r16;
    _sts "current_report + 20", r17;

    _rjmp "send_hid_report";
};

#sends current_report as an hid report
emit_sub "send_hid_report", sub {
    #now, we need to send the hid report
    SELECT_EP r17, EP_1;

    block {
        _lds r17, UEINTX;
        _sbrs r17, RWAL;
        _rjmp begin_label;
    };

    _ldi zl, lo8(current_report);
    _ldi zh, hi8(current_report);

    _ldi r17, 21;

    block {
        _ld r18, "z+";
        _sts UEDATX, r18;
        _dec r17;
        _brne begin_label;
    };

    _lds r17, UEINTX;
    _cbr r17, MASK(FIFOCON);
    _sts UEINTX, r17;
    _ret;
};

my($action_count);
BEGIN {
     $action_count = 0;
}
sub simple_keycode {
    my($keycode) = shift;

    return sub {
        my($button_index) = shift;

        my($press_label) = "simple_press_action_$action_count";
        my($release_label) = "simple_release_action_$action_count";
        $action_count++;

        emit_sub $press_label, sub {
            #store the address for the release routine
            _ldi r16, lo8(pm($release_label));
            _sts "release_table + " . ($button_index * 2), r16;
            _ldi r16, hi8(pm($release_label));
            _sts "release_table + " . (($button_index * 2) + 1), r16;

            _ldi r16, $keycode;
            _rjmp "handle_simple_press";
        };

        emit_sub $release_label, sub {
            _ldi r16, $keycode;
            _rjmp "handle_simple_release";
        };

        return [$release_label, $press_label];
    }
}

sub shifted_keycode {
    my($keycode) = shift;

    return sub {
        my($button_index) = shift;

        my($press_label) = "shifted_press_action_$action_count";
        my($release_label) = "shifted_release_action_$action_count";
        $action_count++;

        emit_sub $press_label, sub {
            #store the address for the release routine
            _ldi r16, lo8(pm($release_label));
            _sts "release_table + " . ($button_index * 2), r16;
            _ldi r16, hi8(pm($release_label));
            _sts "release_table + " . (($button_index * 2) + 1), r16;

            _ldi r16, $keycode;
            _rjmp "handle_shifted_press";
        };

        emit_sub $release_label, sub {
            _ldi r16, $keycode;
            _rjmp "handle_shifted_release";
        };

        return [$release_label, $press_label];
    }
}

sub modifier_keycode {
    my($keycode) = shift;

    return sub {
        my($button_index) = shift;

        my($press_label) = "modifier_press_action_$action_count";
        my($release_label) = "modifier_release_action_$action_count";
        $action_count++;

        emit_sub $press_label, sub {
            #add additional logic for lshift key
            if ($keycode == 0xe1) {
                #set the "physical" flag in lshift_status
                _lds r16, lshift_status;
                _sbr r16, 0b10000000;
                _sts lshift_status, r16;
            }

            #store the address for the release routine
            _ldi r16, lo8(pm($release_label));
            _sts "release_table + " . ($button_index * 2), r16;
            _ldi r16, hi8(pm($release_label));
            _sts "release_table + " . (($button_index * 2) + 1), r16;

            _ldi r16, MASK($keycode - 0xe0);
            _rjmp "handle_modifier_press";
        };

        emit_sub $release_label, sub {
            #add additional logic for lshift key
            if ($keycode == 0xe1) {
                block {
                    #clear the "physical" flag in lshift_status
                    _lds r16, lshift_status;
                    _cbr r16, 0b10000000;
                    _sts lshift_status, r16;

                    #check if the virtual count is > 0, if so, don't release shift
                    _breq end_label;

                    _ret;
                };
            }

            _ldi r16, MASK($keycode - 0xe0);
            _rjmp "handle_modifier_release";
        };

        return [$release_label, $press_label];
    }
}

sub nas_action {
    return sub {
        my($button_index) = shift;

        my($press_label) = "nas_press_action_$action_count";
        my($release_label) = "nas_release_action_$action_count";
        $action_count++;

        emit_sub $press_label, sub {
            #store the address for the release routine
            _ldi r16, lo8(pm($release_label));
            _sts "release_table + " . ($button_index * 2), r16;
            _ldi r16, hi8(pm($release_label));
            _sts "release_table + " . (($button_index * 2) + 1), r16;

            #update the press table pointer for the nas press table
            _ldi r16, lo8("press_table_1");
            _sts current_press_table, r16;
            _ldi r16, hi8("press_table_1");
            _sts "current_press_table + 1", r16;

            _ret;
        };

        emit_sub $release_label, sub {
            #restore the press table pointer from persistent_mode_press_table
            _lds r16, persistent_mode_press_table;
            _sts current_press_table, r16;
            _lds r16, "persistent_mode_press_table + 1";
            _sts "current_press_table + 1", r16;

            _ret;
        };

        return [$release_label, $press_label];
    }
}

sub undefined_action {
    return sub {
        my($button_index) = shift;

        my($press_label) = "undefined_press_action_$action_count";
        my($release_label) = "undefined_release_action_$action_count";
        $action_count++;

        emit_sub $press_label, sub {
            #store the address for the release routine
            _ldi r16, lo8(pm($release_label));
            _sts "release_table + " . ($button_index * 2), r16;
            _ldi r16, hi8(pm($release_label));
            _sts "release_table + " . (($button_index * 2) + 1), r16;

            _ret;
        };

        emit_sub $release_label, sub {
            _ret;
        };

        return [$release_label, $press_label];
    }
}
