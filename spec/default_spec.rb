require 'yaml'

describe 'default application loadbalancer' do
  
  context 'cftest' do
    it 'compiles test' do
      expect(system("cfhighlander cftest #{@validate} --tests tests/default.test.yaml")).to be_truthy
    end
  end
  
  let(:template) { YAML.load_file("#{File.dirname(__FILE__)}/../out/tests/default/loadbalancer.compiled.yaml") }
  
  context 'Resources' do
    let(:resources) { template["Resources"] }

    context 'LoadBalancer' do
      let(:properties) { resources["LoadBalancer"]["Properties"] }

      it 'is an application load balancer' do
        # Type is set in the resource type, not in properties
        expect(resources["LoadBalancer"]["Type"]).to eq("AWS::ElasticLoadBalancingV2::LoadBalancer")
      end

      it 'has the correct attributes' do
        expect(properties["LoadBalancerAttributes"]).to include(
          {"Key" => "idle_timeout.timeout_seconds", "Value" => 120}
        )
      end

      it 'has the correct security groups' do
        expect(properties["SecurityGroups"]).to include({"Ref" => "SecurityGroupLoadBalancer"})
      end
    end

    context 'TargetGroups' do
      it 'creates default target group' do
        expect(resources).to have_key("defaultTargetGroup")
        expect(resources["defaultTargetGroup"]["Properties"]["Port"]).to eq(80)
        expect(resources["defaultTargetGroup"]["Properties"]["Protocol"]).to eq("HTTP")
      end

      it 'creates api target group' do
        expect(resources).to have_key("apiTargetGroup")
        expect(resources["apiTargetGroup"]["Properties"]["Port"]).to eq(80)
        expect(resources["apiTargetGroup"]["Properties"]["Protocol"]).to eq("HTTP")
      end
    end

    context 'Listeners' do
      it 'creates HTTP listener' do
        expect(resources).to have_key("httpListener")
        expect(resources["httpListener"]["Properties"]["Port"]).to eq(80)
        expect(resources["httpListener"]["Properties"]["Protocol"]).to eq("HTTP")
        expect(resources["httpListener"]["Properties"]["DefaultActions"][0]["TargetGroupArn"]).to eq({"Ref" => "defaultTargetGroup"})
      end

      it 'creates listener rules' do
        expect(resources).to have_key("httpRule100")
        expect(resources["httpRule100"]["Properties"]["Priority"]).to eq(100)
        expect(resources["httpRule100"]["Properties"]["Conditions"][0]["Field"]).to eq("path-pattern")
        expect(resources["httpRule100"]["Properties"]["Conditions"][0]["Values"]).to include("/api")
        
        expect(resources).to have_key("httpRule200")
        expect(resources["httpRule200"]["Properties"]["Priority"]).to eq(200)
        expect(resources["httpRule200"]["Properties"]["Conditions"][0]["Field"]).to eq("host-header")
        expect(resources["httpRule200"]["Properties"]["Conditions"][0]["Values"]).to include("api.example.com")
      end
    end

    context 'SecurityGroups' do
      let(:sg_properties) { resources["SecurityGroupLoadBalancer"]["Properties"] }

      it 'creates security group with correct ingress rules' do
        expect(sg_properties["SecurityGroupIngress"]).to include(
          hash_including("FromPort" => "80", "ToPort" => "80", "IpProtocol" => "tcp")
        )
      end
    end
  end

  context 'Outputs' do
    let(:outputs) { template["Outputs"] }

    it 'has load balancer DNS name' do
      expect(outputs).to include("LoadBalancerDNSName")
      expect(outputs["LoadBalancerDNSName"]["Value"]).to eq({"Fn::GetAtt" => ["LoadBalancer", "DNSName"]})
    end

    it 'has load balancer canonical hosted zone ID' do
      expect(outputs).to include("LoadBalancerCanonicalHostedZoneID")
      expect(outputs["LoadBalancerCanonicalHostedZoneID"]["Value"]).to eq({"Fn::GetAtt" => ["LoadBalancer", "CanonicalHostedZoneID"]})
    end
  end
end
