
CloudFormation do

  private = loadbalancer_scheme == 'internal' ? true : false
  # nlb_eip_conditions(maximum_availability_zones) if (loadbalancer_type == 'network') && !(private) && (static_ips)

  EC2_SecurityGroup('SecurityGroupLoadBalancer') do
    GroupDescription FnJoin(' ', [Ref('EnvironmentName'), component_name])
    VpcId Ref('VPCId')
    SecurityGroupIngress sg_create_rules(securityGroups['loadbalancer'], ip_blocks)
  end

  atributes = []

  loadbalancer_attributes.each do |key, value|
    atributes << { Key: key, Value: value } unless value.nil?
  end if defined? loadbalancer_attributes

  tags = []
  tags << { Key: "Environment", Value: Ref("EnvironmentName") }
  tags << { Key: "EnvironmentType", Value: Ref("EnvironmentType") }

  loadbalancer_tags.each do |key, value|
    tags << { Key: key, Value: value }
  end if defined? loadbalancer_tags

  ElasticLoadBalancingV2_LoadBalancer('LoadBalancer') do

    if (loadbalancer_type == 'network') && !(private) && (static_ips)
      SubnetMappings nlb_subnet_mappings('SubnetIds', maximum_availability_zones)
    else
      Scheme 'internal' if private
      Subnets Ref('SubnetIds')
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
  end if defined? targetgroups

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
      Export FnSub("${EnvironmentName}-#{component_name}-#{listener_name}Listener")
    }
  end if defined? listeners

  records.each do |record|
    safe_name = record.gsub('*','Wildcard').gsub('.','Dot').gsub('-','')
    Route53_RecordSet("#{safe_name}LoadBalancerRecord") do
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
  end if defined? records

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
