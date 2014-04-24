require 'puppet'
require 'yaml'
require 'xmpp4r/client'

include Jabber

Puppet::Reports.register_report(:xmpp) do

  configfile = File.join([File.dirname(Puppet.settings[:config]), "xmpp.yaml"])
  raise(Puppet::ParseError, "XMPP report config file #{configfile} not readable") unless File.exist?(configfile)
  begin
    config = YAML.load_file(configfile)
  rescue TypeError => e
    raise Puppet::ParserError, "XMPP Yaml file is invalid!"
  end
  XMPP_SRV = config[:xmpp_server] || nil
  XMPP_JID = config[:xmpp_jid]
  XMPP_PASSWORD = config[:xmpp_password]
  XMPP_TARGET = config[:xmpp_target] || nil
  XMPP_ENV = config[:xmpp_environment] || 'ALL'
  XMPP_MUC = config[:xmpp_muc] || false
  XMPP_MUC_PASSWORD = config[:xmpp_muc_password] || nil
  REGEX = config[:regex] || nil

  desc <<-DESC
  Send notification of failed reports to an XMPP user or MUC.
  DESC

  def process
    xmpp_target = XMPP_TARGET
    xmpp_muc = XMPP_MUC

    self.status != nil ? status = self.status : status = 'undefined'
    self.environment != nil ? environment = self.environment : environment = 'undefined'

    if status == 'failed' or status == 'undefined' then

      if REGEX != nil then
        REGEX.each_key { |key| Puppet.info "Test regex #{key}"
          teststr = REGEX[key][:test]
          if self.host =~ /#{teststr}/ then
            Puppet.info "Host is matching regex '#{teststr}'."
            if REGEX[key][:xmpp_target] != nil then xmpp_target = REGEX[key][:xmpp_target] end
            if REGEX[key][:xmpp_muc] != nil then xmpp_muc = REGEX[key][:xmpp_muc] end
            break
          end
        }
      end

      if xmpp_target != nil and (XMPP_ENV.include?(environment) or XMPP_ENV == 'ALL') then
        jid = JID::new(XMPP_JID)
        cl = Client::new(jid)

        XMPP_SRV != nil ? cl.connect(XMPP_SRV) : cl.connect
        cl.auth(XMPP_PASSWORD)

        body = "Puppet run for #{self.host} #{status} at #{Time.now.asctime}"
        m = Message::new(xmpp_target, body)

        if xmpp_muc or xmpp_muc == 'true' then
          Puppet.info "Sending status for #{self.host} to XMPP MUC #{xmpp_target}"
          require 'xmpp4r/muc'
          muc = MUC::MUCClient.new(cl)
          muc.join(JID::new(xmpp_target + '/' + cl.jid.node), XMPP_MUC_PASSWORD)
          muc.send m
          muc.exit
        else
          Puppet.info "Sending status for #{self.host} to XMMP user #{xmpp_target}"
          cl.send m.set_type(:normal).set_id('1').set_subject("Puppet run failed!")
        end

        cl.close
      end
    end
  end
end
