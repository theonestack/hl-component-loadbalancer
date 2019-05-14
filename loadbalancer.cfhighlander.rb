CfhighlanderTemplate do
  DependsOn 'vpc'
  Name 'loadbalancer'
  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true
    ComponentParam 'StackOctet', isGlobal: true
    ComponentParam 'DnsDomain'

    if defined?(listeners)
      listeners.each do |listener,properties|
        if properties['protocol'] == 'https'
          ComponentParam 'SslCertId'
          properties['certificates'].each do |cert|
            ComponentParam "#{cert}CertificateArn"
          end if properties.has_key?('certificates')
        end
      end
    end

    maximum_availability_zones.times do |az|
      if (loadbalancer_type == 'network') && (loadbalancer_scheme != 'internal') && (static_ips)
        ComponentParam "Nlb#{az}EIPAllocationId", 'dynamic'
      end
    end

    ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
  end
end
