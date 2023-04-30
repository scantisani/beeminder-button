# Beeminder Button

An AWS Lambda function that runs when I press a button in the kitchen.

It calculates how many minutes I got up before 9AM, then sends that to [Beeminder](https://www.beeminder.com) as a datapoint.
If I get up after 9AM, it sends a negative number--except on the weekend, when it'll send `0` instead.
