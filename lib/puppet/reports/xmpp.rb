require 'puppet'
require 'yaml'

begin
  require 'xmpp4r/client'
  include Jabber
rescue LoadError => e
  Puppet.info "You need the `xmpp4r` gem to use the XMPP report"
end

Puppet::Reports.register_report(:xmpp) do

  configfile = File.join([File.dirname(Puppet.settings[:config]), "xmpp.yaml"])
  raise(Puppet::ParseError, "XMPP report config file #{configfile} not readable") unless File.exist?(configfile)
  config = YAML.load_file(configfile)
  XMPP_SRV = config[:xmpp_server] || nil
  XMPP_JID = config[:xmpp_jid]
  XMPP_PASSWORD = config[:xmpp_password]
  XMPP_TARGET = config[:xmpp_target]
  XMPP_ENV = config[:xmpp_environment] || 'ALL'

  desc <<-DESC
  Send notification of failed reports to an XMPP user or MUC.
  DESC

  def process
    if self.status == 'failed' and (XMPP_ENV.include?(self.environment) or XMPP_ENV == 'ALL')
      jid = JID::new(XMPP_JID)
      cl = Client::new(jid)

      XMPP_SRV != nil ? cl.connect(XMPP_SRV) : cl.connect
      cl.auth(XMPP_PASSWORD)

      body = "Puppet run for #{self.host} #{self.status} at #{Time.now.asctime}"
      m = Message::new(XMPP_TARGET, body)

      if XMPP_TARGET =~ /conference/ then
        Puppet.info "Sending status for #{self.host} to XMPP MUC #{XMPP_TARGET}"
        require 'xmpp4r/muc'
        muc = MUC::MUCClient.new(cl)
        muc.join JID::new(XMPP_TARGET + '/' + cl.jid.node)
        muc.send m
        muc.exit
      else
        Puppet.info "Sending status for #{self.host} to XMMP user #{XMPP_TARGET}"
        cl.send m.set_type(:normal).set_id('1').set_subject("Puppet run failed!")
      end

      cl.close
    end
  end
end
