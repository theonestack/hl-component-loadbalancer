
CloudFormation do
  private = false
  if defined?(loadbalancer_scheme) && loadbalancer_scheme == 'internal'
    private = true
  end

  az_conditions_resources('SubnetPublic', maximum_availability_zones) unless private
  az_conditions_resources('SubnetCompute', maximum_availability_zones) if private


  EC2_SecurityGroup('SecurityGroupLoadBalancer') do
    GroupDescription FnJoin(' ', [Ref('EnvironmentName'), component_name])
    VpcId Ref('VPCId')
    SecurityGroupIngress sg_create_rules(securityGroups['loadbalancer'], ip_blocks)
  end

  atributes = []

  loadbalancer_attributes.each do |key, value|
    atributes << { Key: key, Value: value } unless value.nil?
  end if loadbalancer_attributes.any?

  tags = []
  tags << { Key: "Environment", Value: Ref("EnvironmentName") }
  tags << { Key: "EnvironmentType", Value: Ref("EnvironmentType") }

  loadbalancer_tags.each do |key, value|
    tags << { Key: key, Value: value }
  end if loadbalancer_tags.any?

  ElasticLoadBalancingV2_LoadBalancer('LoadBalancer') do

    if loadbalancer_scheme == 'internal'
      Subnets az_conditional_resources('SubnetCompute', maximum_availability_zones)
      Scheme 'internal'
    else
      Subnets az_conditional_resources('SubnetPublic', maximum_availability_zones)
    end

    if loadbalancer_type == 'network'
      Type loadbalancer_type
    else
      SecurityGroups [Ref('SecurityGroupLoadBalancer')]
    end

    Tags tags if tags.any?

    LoadBalancerAttributes atributes if atributes.any?
  end

  targetgroups.each do |tg_name, tg|

    atributes = []

    tg['atributes'].each do |key, value|
      atributes << { Key: key, Value: value }
    end if tg.has_key?('atributes')

    tags = []
    tags << { Key: "Environment", Value: Ref("EnvironmentName") }
    tags << { Key: "EnvironmentType", Value: Ref("EnvironmentType") }

    tg['tags'].each do |key, value|
      tags << { Key: key, Value: value }
    end if tg.has_key?('tags')

    ElasticLoadBalancingV2_TargetGroup("#{tg_name}TargetGroup") do
      ## Required
      Port tg['port']
      Protocol tg['protocol'].upcase
      VpcId Ref('VPCId')
      ## Optional
      if tg.has_key?('healthcheck')
        HealthCheckPort tg['healthcheck']['port'] if tg['healthcheck'].has_key?('port')
        HealthCheckProtocol tg['healthcheck']['protocol'] if tg['healthcheck'].has_key?('port')
        HealthCheckIntervalSeconds tg['healthcheck']['interval'] if tg['healthcheck'].has_key?('interval')
        HealthCheckTimeoutSeconds tg['healthcheck']['timeout'] if tg['healthcheck'].has_key?('timeout')
        HealthyThresholdCount tg['healthcheck']['heathy_count'] if tg['healthcheck'].has_key?('heathy_count')
        UnhealthyThresholdCount tg['healthcheck']['unheathy_count'] if tg['healthcheck'].has_key?('unheathy_count')
        HealthCheckPath tg['healthcheck']['path'] if tg['healthcheck'].has_key?('path')
        Matcher ({ HttpCode: tg['healthcheck']['code'] }) if tg['healthcheck'].has_key?('code')
      end

      TargetType tg['type'] if tg.has_key?('type')
      TargetGroupAttributes atributes if atributes.any?

      Tags tags if tags.any?

      if tg.has_key?('type') and tg['type'] == 'ip' and tg.has_key? 'target_ips'
        Targets (tg['target_ips'].map {|ip|  { 'Id' => ip['ip'], 'Port' => ip['port'] }})
      end
    end

    Output("#{tg_name}TargetGroup") {
      Value(Ref("#{tg_name}TargetGroup"))
      Export FnSub("${EnvironmentName}-#{component_name}-#{tg_name}TargetGroup")
    }
  end if defined?(targetgroups)

  listeners.each do |listener_name, listener|
    next if listener.nil?
    ElasticLoadBalancingV2_Listener("#{listener_name}Listener") do
      Protocol listener['protocol'].upcase
      Certificates [{ CertificateArn: Ref('SslCertId') }] if listener['protocol'] == 'https'
      SslPolicy listener['ssl_policy'] if listener.has_key?('ssl_policy')
      Port listener['port']
      DefaultActions ([
          TargetGroupArn: Ref("#{listener['default_targetgroup']}TargetGroup"),
          Type: "forward"
      ])
      LoadBalancerArn Ref('LoadBalancer')
    end
    Output("#{listener_name}Listener") {
      Value(Ref("#{listener_name}Listener"))
      Export FnSub("${EnvironmentName}-#{component_name}-#{listener_name}Listener")
    }
  end if defined?(listeners)

  if defined? records
    records.each do |record|

      Route53_RecordSet("#{record.gsub('*','Wildcard').gsub('.','Dot')}LoadBalancerRecord") do
        HostedZoneName FnJoin("", [ Ref("EnvironmentName"), ".", Ref('DnsDomain'), "."])
        Name FnJoin("", [ "#{record}.", Ref("EnvironmentName"), ".", Ref('DnsDomain'), "."])
        Type 'A'
        AliasTarget ({
            DNSName: FnGetAtt("LoadBalancer", "DNSName"),
            HostedZoneId: FnGetAtt("LoadBalancer", "CanonicalHostedZoneID")
        })
      end
    end
  end

  Output("LoadBalancer") {
    Value(Ref("LoadBalancer"))
    Export FnSub("${EnvironmentName}-#{component_name}-LoadBalancer")
  }
  Output("SecurityGroupLoadBalancer") {
    Value(Ref("SecurityGroupLoadBalancer"))
    Export FnSub("${EnvironmentName}-#{component_name}-SecurityGroupLoadBalancer")
  }
  Output("LoadBalancerDNSName") {
    Value(FnGetAtt("LoadBalancer", "DNSName"))
    Export FnSub("${EnvironmentName}-#{component_name}-DNSName")
  }
  Output("LoadBalancerCanonicalHostedZoneID") {
    Value(FnGetAtt("LoadBalancer", "CanonicalHostedZoneID"))
    Export FnSub("${EnvironmentName}-#{component_name}-CanonicalHostedZoneID")
  }

end
