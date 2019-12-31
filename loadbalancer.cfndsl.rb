
CloudFormation do

  loadbalancer_scheme = external_parameters[:loadbalancer_scheme]
  maximum_availability_zones = external_parameters[:maximum_availability_zones]
  loadbalancer_type = external_parameters[:loadbalancer_type]
  static_ips = external_parameters[:static_ips]

  private = false
  if loadbalancer_scheme == 'internal'
    private = true
  end

  az_conditions_resources('SubnetPublic', maximum_availability_zones) unless private
  az_conditions_resources('SubnetCompute', maximum_availability_zones) if private
  nlb_eip_conditions(maximum_availability_zones) if (loadbalancer_type == 'network') && !(private) && (static_ips)

  securityGroups = external_parameters[:securityGroups]
  ip_blocks = external_parameters[:ip_blocks]
  EC2_SecurityGroup('SecurityGroupLoadBalancer') do
    GroupDescription FnJoin(' ', [Ref('EnvironmentName'), external_parameters[:component_name]])
    VpcId Ref('VPCId')
    SecurityGroupIngress sg_create_rules(securityGroups['loadbalancer'], ip_blocks)
  end

  atributes = []
  loadbalancer_attributes = external_parameters.fetch(:loadbalancer_attributes, {})
  loadbalancer_attributes.each do |key, value|
    atributes << { Key: key, Value: value } unless value.nil?
  end

  tags = []
  tags << { Key: "Environment", Value: Ref("EnvironmentName") }
  tags << { Key: "EnvironmentType", Value: Ref("EnvironmentType") }

  loadbalancer_tags = external_parameters[:loadbalancer_tags]
  loadbalancer_tags.each do |key, value|
    tags << { Key: key, Value: value }
  end

  loadbalancer_type = external_parameters[:loadbalancer_type]
  ElasticLoadBalancingV2_LoadBalancer('LoadBalancer') do

    if private
      Subnets az_conditional_resources('SubnetCompute', maximum_availability_zones)
      Scheme 'internal'
    elsif (loadbalancer_type == 'network') && !(private) && (static_ips)
      SubnetMappings nlb_subnet_mappings('SubnetPublic', maximum_availability_zones)
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

  targetgroups = external_parameters[:targetgroups]
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
        HealthCheckProtocol tg['healthcheck']['protocol'] if tg['healthcheck'].has_key?('protocol')
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
      Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{tg_name}TargetGroup")
    }
  end

  listeners = external_parameters.fetch(:listeners, {})
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

    if (listener.has_key?('certificates')) && (listener['protocol'] == 'https')
      ElasticLoadBalancingV2_ListenerCertificate("#{listener_name}ListenerCertificate") {
        Certificates listener['certificates'].map { |cert| { CertificateArn: Ref("#{cert}CertificateArn") }  }
        ListenerArn Ref("#{listener_name}Listener")
      }
    end

    listener['rules'].each do |rule|

      listener_conditions = []
      actions = []

      if rule.key?("path")
        listener_conditions << { Field: "path-pattern", Values: [ rule["path"] ] }
      end

      if rule.key?("host")
        hosts = []
        if rule["host"].kind_of?(String) && !rule["host"].include?('.')
          hosts << FnJoin("", [ rule["host"], ".", Ref("EnvironmentName"), ".", Ref('DnsDomain') ])
        else
          hosts << rule["host"]
        end
        listener_conditions << { Field: "host-header", Values: hosts }
      end

      if rule.key?("targetgroup")
        actions << { Type: "forward", TargetGroupArn: Ref("#{rule['targetgroup']}TargetGroup") }
      end

      if rule.key?("redirect")
        actions << { Type: "redirect", RedirectConfig: rule['redirect'] }
      end

      ElasticLoadBalancingV2_ListenerRule("#{listener_name}Rule#{rule['priority']}") do
        Actions actions
        Conditions listener_conditions
        ListenerArn Ref("#{listener_name}Listener")
        Priority rule['priority'].to_i
      end

    end if listener.has_key?('rules')

    Output("#{listener_name}Listener") {
      Value(Ref("#{listener_name}Listener"))
      Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{listener_name}Listener")
    }
  end

  records = external_parameters.fetch(:records, [])
  records.each do |record|
    Route53_RecordSet("#{record.gsub('*','Wildcard').gsub('.','Dot')}LoadBalancerRecord") do
      HostedZoneName FnJoin("", [ Ref("EnvironmentName"), ".", Ref('DnsDomain'), "."])
      if record == 'apex' || record == ''
        Name FnJoin("", [ Ref("EnvironmentName"), ".", Ref('DnsDomain'), "."])
      else
        Name FnJoin("", [ "#{record}.", Ref("EnvironmentName"), ".", Ref('DnsDomain'), "."])
      end
      Type 'A'
      AliasTarget ({
          DNSName: FnGetAtt("LoadBalancer", "DNSName"),
          HostedZoneId: FnGetAtt("LoadBalancer", "CanonicalHostedZoneID")
      })
    end
  end

  Output("LoadBalancer") {
    Value(Ref("LoadBalancer"))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-LoadBalancer")
  }
  Output("SecurityGroupLoadBalancer") {
    Value(Ref("SecurityGroupLoadBalancer"))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-SecurityGroupLoadBalancer")
  }
  Output("LoadBalancerDNSName") {
    Value(FnGetAtt("LoadBalancer", "DNSName"))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-DNSName")
  }
  Output("LoadBalancerCanonicalHostedZoneID") {
    Value(FnGetAtt("LoadBalancer", "CanonicalHostedZoneID"))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-CanonicalHostedZoneID")
  }
  Output("LoadBalancerFullName") {
    Value(FnGetAtt("LoadBalancer", "LoadBalancerFullName"))
    Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-LoadBalancerFullName")
  }

end
