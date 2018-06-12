CfhighlanderTemplate do
  DependsOn 'vpc@1.1.0'
  Name 'loadbalancer'
  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', isGlobal: true
    ComponentParam 'StackOctet', isGlobal: true
    MappingParam('DnsDomain') do
      map 'AccountId'
      attribute 'DnsDomain'
    end
    MappingParam('SslCertId') do
      map 'AccountId'
      attribute 'SslCertId'
    end
    subnet_parameters({'public'=>{'name'=>'Public'}}, maximum_availability_zones)
    subnet_parameters({'compute'=>{'name'=>'Compute'}}, maximum_availability_zones) if defined?(loadbalancer_scheme) && loadbalancer_scheme == 'internal'
    OutputParam component: 'vpc', name: "VPCId"
  end
end
