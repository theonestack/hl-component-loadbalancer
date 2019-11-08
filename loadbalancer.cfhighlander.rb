CfhighlanderTemplate do
  DependsOn 'vpc'
  Name 'loadbalancer'
  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true
    ComponentParam 'StackOctet', isGlobal: true
    ComponentParam 'NetworkPrefix', '10', isGlobal: true
    MappingParam('DnsDomain') do
      map 'AccountId'
      attribute 'DnsDomain'
    end

    if defined?(listeners)
      listeners.each do |listener,properties|
        if properties['protocol'] == 'https'
          MappingParam('SslCertId') do
            map 'AccountId'
            attribute 'SslCertId'
          end
          properties['certificates'].each do |cert|
            ComponentParam "#{cert}CertificateArn"
          end if properties.has_key?('certificates')
        end
      end
    end

    maximum_availability_zones.times do |az|
      private = false
      if defined?(loadbalancer_scheme) && loadbalancer_scheme == 'internal'
        private = true
      end
      ComponentParam "SubnetPublic#{az}" unless private
      ComponentParam "SubnetCompute#{az}" if private
      if (loadbalancer_type == 'network') && !(private) && (static_ips)
        ComponentParam "Nlb#{az}EIPAllocationId", 'dynamic'
      end
    end

    ComponentParam 'VPCId', type: 'AWS::EC2::VPC::Id'
  end
end
