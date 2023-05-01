require "./lambda_function"
require "timecop"
require "webmock/rspec"

RSpec.describe "Lambda function" do
  subject(:lambda) { lambda_handler(event: {}, context: {}) }

  let(:headers) { {"Content-Type" => "application/json"} }
  let(:beeminder_token) { "token" }

  let(:comment) { "via MyStrom Button" }

  let(:get_url) { "https://www.beeminder.com/api/v1/users/dwarvensphere/goals/upbeforenine/datapoints.json?auth_token=#{beeminder_token}" }
  let(:get_response_code) { 200 }
  let(:get_response_body) { '[{"value":10.0,"id":"000000000000000000000000","daystamp":"20230401"}]' }

  let(:post_url) { "https://www.beeminder.com/api/v1/users/dwarvensphere/goals/upbeforenine/datapoints.json" }
  let(:post_response_code) { 200 }
  let(:post_response_body) { '{"value":10.0,"id":"000000000000000000000000","daystamp":"20230403"}' }

  let(:tz) { TZInfo::Timezone.get("Europe/London") }
  let(:time) { tz.local_time(2023, 4, 3, 8, 30, 0) }

  before do
    ENV["BEEMINDER_TOKEN"] = beeminder_token
    allow($stdout).to receive(:puts)

    stub_request(:get, get_url).to_return(status: get_response_code, body: get_response_body)
    stub_request(:post, post_url).to_return(status: post_response_code, body: post_response_body)

    Timecop.travel(time)
  end

  context "when Beeminder does not authorize reading datapoints" do
    let(:get_response_code) { 401 }
    let(:get_response_body) { '{"errors":{"auth_token":"bad_token","message":"No such auth_token found. (Did you mix up auth_token and access_token?)"}}' }

    it "returns 'unprocessable entity'" do
      expect(lambda[:statusCode]).to eq(422)
    end

    it "explains that Beeminder refused the request" do
      expect(lambda[:body]).to match(/request refused by beeminder/i)
    end

    it "does not attempt to add a new datapoint" do
      lambda
      expect(a_request(:post, post_url)).not_to have_been_made
    end

    it "logs the exception" do
      lambda
      expect($stdout).to have_received(:puts).with('401: {"errors":{"auth_token":"bad_token","message":"No such auth_token found. (Did you mix up auth_token and access_token?)"}}')
    end
  end

  context "when Beeminder does not authorize adding a datapoint" do
    let(:post_response_code) { 401 }
    let(:post_response_body) { '{"errors":{"auth_token":"bad_token","message":"No such auth_token found. (Did you mix up auth_token and access_token?)"}}' }

    before { allow($stdout).to receive(:puts) }

    it "returns 'unprocessable entity'" do
      expect(lambda[:statusCode]).to eq(422)
    end

    it "explains that Beeminder refused the request" do
      expect(lambda[:body]).to match(/request refused by beeminder/i)
    end

    it "logs the exception" do
      lambda
      expect($stdout).to have_received(:puts).with('401: {"errors":{"auth_token":"bad_token","message":"No such auth_token found. (Did you mix up auth_token and access_token?)"}}')
    end
  end

  context "when invoked before 9AM" do
    let(:time) { tz.local_time(2023, 4, 3, 8, 30, 0) }
    let(:expected_daystamp) { "20230403" }
    let(:expected_minutes) { 30 }

    it "sends the time difference to Beeminder as a datapoint" do
      lambda

      expect(a_request(:post, post_url)
        .with(
          body: "{\"auth_token\":\"#{beeminder_token}\",\"comment\":\"#{comment}\",\"daystamp\":\"#{expected_daystamp}\",\"value\":#{expected_minutes}}",
          headers: headers
        ))
        .to have_been_made
    end

    it "returns a successful status" do
      expect(lambda[:statusCode]).to eq(200)
    end

    it "includes the datapoint that was sent in the body" do
      expect(lambda[:body]).to match(/sent datapoint '#{expected_minutes}' to beeminder/i)
    end

    it "logs that the datapoint was sent" do
      lambda
      expect($stdout).to have_received(:puts).with(/sent datapoint '#{expected_minutes}' to beeminder/i)
    end

    context "and before 5AM" do
      let(:time) { tz.local_time(2023, 4, 3, 4, 30, 0) }

      it "returns 'unprocessable entity'" do
        expect(lambda[:statusCode]).to eq(422)
      end

      it "explains that the request was sent too early" do
        expect(lambda[:body]).to match(/button pressed before 5AM/i)
      end

      it "logs that the request was sent too early" do
        lambda
        expect($stdout).to have_received(:puts).with(/button pressed before 5AM/i)
      end
    end
  end

  context "when invoked after 9AM" do
    let(:time) { tz.local_time(2023, 4, 3, 9, 15, 0) }
    let(:expected_daystamp) { "20230403" }
    let(:expected_minutes) { -15 }

    it "sends the negative time difference to Beeminder as a datapoint" do
      lambda

      expect(a_request(:post, post_url)
        .with(
          body: "{\"auth_token\":\"#{beeminder_token}\",\"comment\":\"#{comment}\",\"daystamp\":\"#{expected_daystamp}\",\"value\":#{expected_minutes}}",
          headers: headers
        ))
        .to have_been_made
    end

    it "returns a successful status" do
      expect(lambda[:statusCode]).to eq(200)
    end

    it "includes the datapoint that was sent in the body" do
      expect(lambda[:body]).to match(/sent datapoint '#{expected_minutes}' to beeminder/i)
    end

    it "logs that the datapoint was sent" do
      lambda
      expect($stdout).to have_received(:puts).with(/sent datapoint '#{expected_minutes}' to beeminder/i)
    end

    context "when it is the weekend" do
      let(:time) { tz.local_time(2023, 4, 2, 9, 15, 0) }
      let(:expected_daystamp) { "20230402" }
      let(:expected_minutes) { 0 }

      it "sends '0' to Beeminder as a datapoint" do
        lambda

        expect(a_request(:post, post_url)
          .with(
            body: "{\"auth_token\":\"#{beeminder_token}\",\"comment\":\"#{comment}\",\"daystamp\":\"#{expected_daystamp}\",\"value\":#{expected_minutes}}",
            headers: headers
          ))
          .to have_been_made
      end

      it "returns a successful status" do
        expect(lambda[:statusCode]).to eq(200)
      end

      it "includes the datapoint that was sent in the body" do
        expect(lambda[:body]).to match(/sent datapoint '#{expected_minutes}' to beeminder/i)
      end

      it "logs that the datapoint was sent" do
        lambda
        expect($stdout).to have_received(:puts).with(/sent datapoint '#{expected_minutes}' to beeminder/i)
      end
    end
  end

  context "when a datapoint has already been set for that day" do
    let(:get_response_body) { '[{"value":10.0,"id":"000000000000000000000000","daystamp":"20230403"}]' }

    it "does not overwrite the datapoint" do
      lambda
      expect(a_request(:post, post_url)).not_to have_been_made
    end

    it "returns 'unprocessable entity'" do
      expect(lambda[:statusCode]).to eq(422)
    end

    it "explains that there is already a datapoint for the day" do
      expect(lambda[:body]).to match(/datapoint for \\"20230403\\" already exists/i)
    end

    it "logs that the datapoint already exists" do
      lambda
      expect($stdout).to have_received(:puts).with(/datapoint for "20230403" already exists/i)
    end
  end

  context "when the clocks have gone back" do
    let(:time) { tz.local_time(2023, 11, 3, 8, 30, 0) }
    let(:expected_daystamp) { "20231103" }
    let(:expected_minutes) { 30 }

    it "sends the time difference to Beeminder as a datapoint" do
      lambda

      expect(a_request(:post, post_url)
        .with(
          body: "{\"auth_token\":\"#{beeminder_token}\",\"comment\":\"#{comment}\",\"daystamp\":\"#{expected_daystamp}\",\"value\":#{expected_minutes}}",
          headers: headers
        ))
        .to have_been_made
    end

    it "returns a successful status" do
      expect(lambda[:statusCode]).to eq(200)
    end

    it "includes the datapoint that was sent in the body" do
      expect(lambda[:body]).to match(/sent datapoint '#{expected_minutes}' to beeminder/i)
    end

    it "logs that the datapoint was sent" do
      lambda
      expect($stdout).to have_received(:puts).with(/sent datapoint '#{expected_minutes}' to beeminder/i)
    end
  end
end
