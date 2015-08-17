#
# Copyright 2015 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package snmp_standard::mode::listinterfaces;

use base qw(centreon::plugins::mode);

use strict;
use warnings;

my $oid_speed32 = '.1.3.6.1.2.1.2.2.1.5'; # in b/s
my $oid_speed64 = '.1.3.6.1.2.1.31.1.1.1.15';

sub set_oids_status {
    my ($self, %options) = @_;
    
    $self->{oid_adminstatus} = '.1.3.6.1.2.1.2.2.1.7';
    $self->{oid_adminstatus_mapping} = {
        1 => 'up', 2 => 'down', 3 => 'testing', 4 => 'unknown', 5 => 'dormant', 6 => 'notPresent', 7 => 'lowerLayerDown',
    };
    $self->{oid_opstatus} = '.1.3.6.1.2.1.2.2.1.8';
    $self->{oid_opstatus_mapping} = {
        1 => 'up', 2 => 'down', 3 => 'testing', 4 => 'unknown', 5 => 'dormant', 6 => 'notPresent', 7 => 'lowerLayerDown',
    };
}

sub check_oids_label {
    my ($self, %options) = @_;
    
    foreach (('oid_filter', 'oid_display')) {
        $self->{option_results}->{$_} = lc($self->{option_results}->{$_}) if (defined($self->{option_results}->{$_}));
        if (!defined($self->{oids_label}->{$self->{option_results}->{$_}})) {
            my $label = $_;
            $label =~ s/_/-/g;
            $self->{output}->add_option_msg(short_msg => "Unsupported oid in --" . $label . " option.");
            $self->{output}->option_exit();
        }
    }
}

sub set_oids_label {
    my ($self, %options) = @_;

    $self->{oids_label} = {
        'ifdesc' => '.1.3.6.1.2.1.2.2.1.2',
        'ifalias' => '.1.3.6.1.2.1.31.1.1.1.18',
        'ifname' => '.1.3.6.1.2.1.31.1.1.1.1',
    };
}

sub default_oid_filter_name {
    my ($self, %options) = @_;
    
    return 'ifname';
}

sub default_oid_display_name {
    my ($self, %options) = @_;
    
    return 'ifname';
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => defined($options{package}) ? $options{package} : __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                { 
                                  "name"                    => { name => 'use_name' },
                                  "interface:s"             => { name => 'interface' },
                                  "speed:s"                 => { name => 'speed' },
                                  "filter-status:s"         => { name => 'filter_status' },
                                  "skip-speed0"             => { name => 'skip_speed0' },
                                  "use-adminstatus"         => { name => 'use_adminstatus' },
                                  "oid-filter:s"            => { name => 'oid_filter', default => $self->default_oid_filter_name() },
                                  "oid-display:s"           => { name => 'oid_display', default => $self->default_oid_display_name() },
                                  "display-transform-src:s" => { name => 'display_transform_src' },
                                  "display-transform-dst:s" => { name => 'display_transform_dst' },
                                  "add-extra-oid:s@"        => { name => 'add_extra_oid' },
                                });

    $self->{interface_id_selected} = [];
    
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    $self->set_oids_label();
    $self->check_oids_label();
    $self->set_oids_status();
    
    $self->{extra_oids} = {};
    foreach (@{$self->{option_results}->{add_extra_oid}}) {
        next if ($_ eq '');
        my ($name, $oid) = split /,/;
        if (!defined($oid) || $oid !~ /^(\.\d+){1,}$/ || $name eq '') {
            $self->{output}->add_option_msg(short_msg => "Wrong syntax for add-extra-oid '" . $_ . "' option.");
            $self->{output}->option_exit();
        }
        $self->{extra_oids}->{$name} = $oid;
    }
}

sub run {
    my ($self, %options) = @_;
    $self->{snmp} = $options{snmp};

    $self->manage_selection();
    my $result = $self->get_additional_information();
    
    foreach (sort @{$self->{interface_id_selected}}) {
        my $display_value = $self->get_display_value(id => $_);

        my $interface_speed = (defined($result->{$oid_speed64 . "." . $_}) && $result->{$oid_speed64 . "." . $_} ne '' && $result->{$oid_speed64 . "." . $_} != 0 ? 
            ($result->{$oid_speed64 . "." . $_}) : (sprintf("%g", $result->{$oid_speed32 . "." . $_} / 1000 / 1000)));        
        if (defined($self->{option_results}->{speed}) && $self->{option_results}->{speed} ne '') {
            $interface_speed = $self->{option_results}->{speed};
        }
        
        if (defined($self->{option_results}->{skip_speed0}) && $interface_speed == 0) {
            $self->{output}->output_add(long_msg => "Skipping interface '" . $display_value . "': interface speed is 0 and option --skip-speed0 is set");
            next;
        }
        if (defined($self->{option_results}->{filter_status}) && defined($result->{$self->{oid_opstatus} . "." . $_}) && 
            $self->{oid_opstatus_mapping}->{$result->{$self->{oid_opstatus} . "." . $_}} !~ /$self->{option_results}->{filter_status}/i) {
            $self->{output}->output_add(long_msg => "Skipping interface '" . $display_value . "': no matching filter status");
            next;
        }
        if (defined($self->{option_results}->{use_adminstatus}) && defined($result->{$self->{oid_adminstatus} . "." . $_}) && 
            $self->{oid_adminstatus_mapping}->{$result->{$self->{oid_adminstatus} . "." . $_}} ne 'up') {
            $self->{output}->output_add(long_msg => "Skipping interface '" . $display_value . "': adminstatus is not 'up' and option --use-adminstatus is set");
            next;
        }
        my $extra_display = '';
        my $extra_display_append = ' ';
        foreach my $name (keys %{$self->{extra_oids}}) {
            $extra_display .= $extra_display_append . $name . ' = ' . (defined($result->{$self->{extra_oids}->{$name} . "." . $_}) ? $result->{$self->{extra_oids}->{$name} . "." . $_} : '');
            $extra_display_append = ', ';
        }

        $self->{output}->output_add(long_msg => "'" . $display_value . "' [speed = $interface_speed, status = " . $self->{oid_opstatus_mapping}->{$result->{$self->{oid_opstatus} . "." . $_}} . ', id = ' . $_ . $extra_display . ']');
    }

    $self->{output}->output_add(severity => 'OK',
                                short_msg => 'List interfaces:');
    $self->{output}->display(nolabel => 1, force_ignore_perfdata => 1, force_long_output => 1);
    $self->{output}->exit();
}

sub get_additional_information {
    my ($self, %options) = @_;

    my $oids = [$oid_speed32];
    push @$oids, $self->{oid_adminstatus} if (defined($self->{oid_adminstatus}));
    push @$oids, $self->{oid_opstatus} if (defined($self->{oid_opstatus}));
    push @$oids, $oid_speed64 if (!$self->{snmp}->is_snmpv1());  
    if (scalar(keys %{$self->{extra_oids}}) > 0) {
        push @$oids, values %{$self->{extra_oids}};
    }
    
    $self->{snmp}->load(oids => $oids, instances => $self->{interface_id_selected});
    return $self->{snmp}->get_leef();
}

sub get_display_value {
    my ($self, %options) = @_;
    my $value = $self->{datas}->{$self->{option_results}->{oid_display} . "_" . $options{id}};

    if (defined($self->{option_results}->{display_transform_src})) {
        $self->{option_results}->{display_transform_dst} = '' if (!defined($self->{option_results}->{display_transform_dst}));
        eval "\$value =~ s{$self->{option_results}->{display_transform_src}}{$self->{option_results}->{display_transform_dst}}";
    }
    return $value;
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{datas} = {};
    my $result = $self->{snmp}->get_table(oid => $self->{oids_label}->{$self->{option_results}->{oid_filter}});
    $self->{datas}->{all_ids} = [];
    foreach my $key ($self->{snmp}->oid_lex_sort(keys %$result)) {
        next if ($key !~ /^$self->{oids_label}->{$self->{option_results}->{oid_filter}}\.(.*)$/);
        $self->{datas}->{$self->{option_results}->{oid_filter} . "_" . $1} = $self->{output}->to_utf8($result->{$key});
        push @{$self->{datas}->{all_ids}}, $1;
    }
    
    if (scalar(@{$self->{datas}->{all_ids}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "Can't get interfaces...");
        $self->{output}->option_exit();
    }

    if ($self->{option_results}->{oid_filter} ne $self->{option_results}->{oid_display}) {
       $result = $self->{snmp}->get_table(oid => $self->{oids_label}->{$self->{option_results}->{oid_display}});
       foreach my $key ($self->{snmp}->oid_lex_sort(keys %$result)) {
            next if ($key !~ /^$self->{oids_label}->{$self->{option_results}->{oid_display}}\.(.*)$/);
            $self->{datas}->{$self->{option_results}->{oid_display} . "_" . $1} = $self->{output}->to_utf8($result->{$key});
       }
    }
    
    if (!defined($self->{option_results}->{use_name}) && defined($self->{option_results}->{interface})) {
        foreach (@{$self->{datas}->{all_ids}}) {
            if ($self->{option_results}->{interface} =~ /(^|\s|,)$_(\s*,|$)/) {
                push @{$self->{interface_id_selected}}, $_;
            }
        }
    } else {
        foreach (@{$self->{datas}->{all_ids}}) {
            my $filter_name = $self->{datas}->{$self->{option_results}->{oid_filter} . "_" . $_};
            next if (!defined($filter_name));
            
            if (!defined($self->{option_results}->{interface})) {
                push @{$self->{interface_id_selected}}, $_;
                next;
            }
            if ($filter_name =~ /$self->{option_results}->{interface}/) {
                push @{$self->{interface_id_selected}}, $_; 
            }
        }
    }
    
    if (scalar(@{$self->{interface_id_selected}}) <= 0 && !defined($options{disco})) {
        $self->{output}->add_option_msg(short_msg => "No entry found");
        $self->{output}->option_exit();
    }
}

sub disco_format {
    my ($self, %options) = @_;
    
    my $names = ['name', 'total', 'status', 'interfaceid'];
    if (scalar(keys %{$self->{extra_oids}}) > 0) {
        push @$names, keys %{$self->{extra_oids}};
    }
    $self->{output}->add_disco_format(elements => $names);
}

sub disco_show {
    my ($self, %options) = @_;
    $self->{snmp} = $options{snmp};

    $self->manage_selection(disco => 1);
    return if (scalar(@{$self->{interface_id_selected}}) == 0);
    my $result = $self->get_additional_information();
    foreach (sort @{$self->{interface_id_selected}}) {
        my $display_value = $self->get_display_value(id => $_);
        
        my $interface_speed = (defined($result->{$oid_speed64 . "." . $_}) && $result->{$oid_speed64 . "." . $_} ne '' && $result->{$oid_speed64 . "." . $_} != 0 ? 
            ($result->{$oid_speed64 . "." . $_}) : (sprintf("%g", $result->{$oid_speed32 . "." . $_} / 1000 / 1000)));
        if (defined($self->{option_results}->{speed}) && $self->{option_results}->{speed} ne '') {
            $interface_speed = $self->{option_results}->{speed};
        }
        next if (defined($self->{option_results}->{skip_speed0}) && $interface_speed == 0);
        next if (defined($self->{option_results}->{filter_status}) && defined($result->{$self->{oid_opstatus} . "." . $_}) && 
            $self->{oid_opstatus_mapping}->{$result->{$self->{oid_opstatus} . "." . $_}} !~ /$self->{option_results}->{filter_status}/i);
        next if (defined($self->{option_results}->{use_adminstatus}) && defined($result->{$self->{oid_adminstatus} . "." . $_}) && 
            $self->{oid_adminstatus_mapping}->{$result->{$self->{oid_adminstatus} . "." . $_}} ne 'up');
        
        my %extra_values = ();
        foreach my $name (keys %{$self->{extra_oids}}) {
            $extra_values{$name} = defined($result->{$self->{extra_oids}->{$name} . "." . $_}) ?
                $result->{$self->{extra_oids}->{$name} . "." . $_} : '';
        }
        
        $self->{output}->add_disco_entry(name => $display_value,
                                         total => $interface_speed,
                                         status => $self->{oid_opstatus_mapping}->{$result->{$self->{oid_opstatus} . "." . $_}},
                                         interfaceid => $_,
                                         %extra_values);
    }
}

1;

__END__

=head1 MODE

=over 8

=item B<--interface>

Set the interface (number expected) ex: 1,2,... (empty means 'check all interface').

=item B<--name>

Allows to use interface name with option --interface instead of interface oid index (Can be a regexp)

=item B<--speed>

Set interface speed (in Mb).

=item B<--skip-speed0>

Don't display interface with speed 0.

=item B<--filter-status>

Display interfaces matching the filter (example: 'up').

=item B<--use-adminstatus>

Display interfaces with AdminStatus 'up'.

=item B<--oid-filter>

Choose OID used to filter interface (default: ifName) (values: ifDesc, ifAlias, ifName).

=item B<--oid-display>

Choose OID used to display interface (default: ifName) (values: ifDesc, ifAlias, ifName).

=item B<--display-transform-src>

Regexp src to transform display value. (security risk!!!)

=item B<--display-transform-dst>

Regexp dst to transform display value. (security risk!!!)

=item B<--add-extra-oid>

Display an OID. Example: --add-extra-oid='alias,.1.3.6.1.2.1.31.1.1.1.18'

=back

=cut
