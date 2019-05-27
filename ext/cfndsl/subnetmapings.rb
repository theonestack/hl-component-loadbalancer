# def nlb_subnet_mappings(resource_name, azs)
#   if azs.to_i > 0
#     resources = []
#     azs.times do |az|
#       resources << { SubnetId: FnSelect(az, resource_name), AllocationId: Ref("Nlb#{az}EIPAllocationId") }
#     end
#     if_statement = FnIf("#{azs-1}#{resource_name}", resources, nlb_subnet_mappings(resource_name, azs - 1)) if azs>1
#     if_statement = { SubnetId: FnSelect(az, resource_name), AllocationId: Ref("Nlb#{azs}EIPAllocationId") } if azs == 1
#     if_statement
#   else
#     { SubnetId: Ref("#{resource_name}#{azs}"), AllocationId: Ref("Nlb#{azs}EIPAllocationId") }
#   end
# end
#
# def nlb_eip_conditions(azs)
#   azs.times { |az| Condition("Nlb#{az}EIPRequired", FnEquals(Ref("Nlb#{az}EIPAllocationId"), 'dynamic')) }
# end

def nlb_subnet_mappings(subnets, azs)
  azs.times.collect { |az| { SubnetId: FnSelect(az, Ref(subnets)), AllocationId: Ref("Nlb#{az}EIPAllocationId") } }
end
