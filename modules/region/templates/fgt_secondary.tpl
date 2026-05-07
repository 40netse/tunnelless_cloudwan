Content-Type: multipart/mixed; boundary="==FORTIGATE=="
MIME-Version: 1.0

--==FORTIGATE==
Content-Type: text/plain; charset="us-ascii"

config system global
    set hostname "${hostname}"
    set admintimeout 480
    set admin-sport 443
    set timezone 04
end

config system admin
    edit "admin"
        set password "${admin_password}"
    next
end

config system interface
    edit "port1"
        set mode static
        set ip ${port1_ip} ${port1_mask}
        set allowaccess ping https ssh fgfm
        set description "public"
    next
    edit "port2"
        set mode static
        set ip ${port2_ip} ${port2_mask}
        set allowaccess ping
        set description "private-cloudwan"
    next
    edit "port3"
        set mode static
        set ip ${port3_ip} ${port3_mask}
        set allowaccess ping https ssh
        set description "ha-sync-mgmt"
    next
end

config router static
    edit 1
        set gateway ${port1_gw}
        set device "port1"
    next
    edit 2
        set dst ${spoke_a_net} ${spoke_a_mask}
        set gateway ${port2_gw}
        set device "port2"
    next
    edit 3
        set dst ${spoke_b_net} ${spoke_b_mask}
        set gateway ${port2_gw}
        set device "port2"
    next
    edit 4
        set dst ${remote_spoke_a_net} ${remote_spoke_a_mask}
        set gateway ${port2_gw}
        set device "port2"
    next
    edit 5
        set dst ${remote_spoke_b_net} ${remote_spoke_b_mask}
        set gateway ${port2_gw}
        set device "port2"
    next
end

config system ha
    set group-name "${ha_group_name}"
    set group-id 1
    set mode a-p
    set password "${ha_password}"
    set hbdev "port3" 50
    set session-pickup enable
    set ha-mgmt-status enable
    config ha-mgmt-interfaces
        edit 1
            set interface "port3"
            set gateway ${port3_gw}
        next
    end
    set priority 1
    set override disable
    set unicast-hb enable
    set unicast-hb-peerip ${ha_peer_ip}
end

config router bgp
    set as ${fgt_asn}
    set router-id ${port2_ip}
    config neighbor
        edit "${cne_bgp_ip}"
            set remote-as ${cne_asn}
            set soft-reconfiguration enable
            set ebgp-enforce-multihop enable
            set ebgp-multihop-ttl 255
            set update-source "port2"
        next
    end
    config network
        edit 1
            set prefix ${spoke_a_net} ${spoke_a_mask}
        next
        edit 2
            set prefix ${spoke_b_net} ${spoke_b_mask}
        next
    end
end

config firewall policy
    edit 1
        set name "spoke-to-cloudwan"
        set srcintf "port2"
        set dstintf "port2"
        set srcaddr "all"
        set dstaddr "all"
        set action accept
        set schedule "always"
        set service "ALL"
        set logtraffic all
    next
end

--==FORTIGATE==--
