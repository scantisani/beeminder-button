require "json"
require "net/http"
require "uri"

DATAPOINT_ENDPOINT = "https://www.beeminder.com/api/v1/users/dwarvensphere/goals/upbeforenine/datapoints.json"
HEADERS = {"Content-Type" => "application/json"}

def lambda_handler(event:, context:)
  return button_pressed_before_five if before_five_am?
  return datapoint_already_exists if datapoint_exists?

  update_beeminder
  successful_request
rescue Net::HTTPClientException, Net::HTTPFatalError => e
  puts "#{e.response.code}: #{e.response.body}"
  request_refused
end

def before_five_am?
  (minutes_before_nine / 60) > 4
end

def minutes_before_nine
  nine_am_today = Time.new(now.year, now.month, now.day, 9, 0, 0)

  (nine_am_today - now) / 60
end

def now
  @now ||= Time.now
end

def button_pressed_before_five
  message = "Button pressed before 5AM"

  puts message
  {statusCode: 422, body: JSON.generate(message)}
end

def datapoint_exists?
  response = Net::HTTP.get_response(URI("#{DATAPOINT_ENDPOINT}?auth_token=#{token}"))
  response.error! unless response.code == "200"

  datapoints = JSON.parse(response.body)
  datapoints.any? { |datapoint| datapoint["daystamp"] == daystamp }
end

def token
  ENV["BEEMINDER_TOKEN"]
end

def datapoint_already_exists
  message = "Datapoint for \"#{daystamp}\" already exists"

  puts message
  {statusCode: 422, body: JSON.generate(message)}
end

def daystamp
  now.strftime("%Y%m%d")
end

def update_beeminder
  parameters = {"auth_token" => ENV["BEEMINDER_TOKEN"], "comment" => "via MyStrom Button", "daystamp" => daystamp, "value" => datapoint}

  Net::HTTP.post(URI(DATAPOINT_ENDPOINT), parameters.to_json, HEADERS).tap do |response|
    response.error! unless response.code == "200"
  end
end

def datapoint
  time_difference = minutes_before_nine.ceil.to_i

  weekend? ? [0, time_difference].max : time_difference
end

def weekend?
  now.saturday? || now.sunday?
end

def successful_request
  message = "Sent datapoint '#{datapoint}' to Beeminder!"

  puts message
  {statusCode: 200, body: JSON.generate(message)}
end

def request_refused
  message = "Request refused by Beeminder"

  puts message
  {statusCode: 422, body: JSON.generate(message)}
end
