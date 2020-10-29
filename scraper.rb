require 'httparty'

class Scraper
  include HTTParty
  API_KEY = 'YOUR_API_KEY'
  QUERY_URI = 'https://euw1.api.riotgames.com/tft/summoner/v1/summoners/by-name/'
  MATCH_URI = 'https://europe.api.riotgames.com/tft/match/v1/matches/'

  def initialize(summoner_name)
    @summoner_name = summoner_name
  end

  def work
    @summoner_info = Scraper::SummonerQuery.new(@summoner_name).fetch_summoner_info
    @summoner_matches = Scraper::SummonerMatches.new(@summoner_info[:puuid]).fetch_match_ids
    @match_participants = Scraper::MatchParticipants.new(@summoner_matches).generate_participants
    @enqueue_participants = Scraper::EnqueueParticipants.new(@match_participants).enqueue
  end

  class SummonerQuery
    def initialize(summoner_name)
      @summoner_name = summoner_name
    end

    def fetch_summoner_info
      uri = URI.parse(URI.escape("#{QUERY_URI}#{@summoner_name}?api_key=#{API_KEY}"))

      response = HTTParty.get(uri, format: :plain)

      if response.code == 200
        return JSON.parse response, symbolize_names: true
      elsif response.code ==  429
        puts "[RATE_LIMIT] API REQUEST FAILED - #fetch_summoner_info"
      else
        puts "[smth else] API REQUEST FAILED - #fetch_summoner_info"
      end
    end
  end

  class SummonerMatches
    RESULT_COUNT = 50

    def initialize(puuid)
      @puuid = puuid
    end

    def fetch_match_ids
      response = HTTParty.get("#{MATCH_URI}by-puuid/#{@puuid}/ids?count=#{RESULT_COUNT}&api_key=#{API_KEY}", format: :plain)
      
      if response.code == 200
        return JSON.parse response, symbolize_names: true
      elsif response.code == 429
        puts "[RATE_LIMIT] API REQUEST FAILED - #fetch_match_ids"
      else
        puts "[smth else] API REQUEST FAILED - #fetch_match_ids"
      end
    end
  end

  class MatchParticipants
    def initialize(match_ids)
      @match_ids = match_ids
    end

    def generate_participants
      @participants = []

      File.open('results.txt', 'a+') do |file|
        @match_ids.each do |match|
          response = HTTParty.get("#{MATCH_URI}#{match}?api_key=#{API_KEY}", format: :plain)

          if response.code == 200
            symbolized_response =  JSON.parse response, symbolize_names: true
            participants_to_write = symbolized_response[:metadata][:participants]

            participants_to_write.each do |game_participant|
              file.write("#{game_participant}\n") if !participant_exists?(game_participant)
            end

            @participants << symbolized_response[:metadata][:participants]
          elsif response.code == 429
            puts "[429] API REQUEST FAILED - #generate_participants"
          else
            puts "API REQUEST FAILED - #generate_participants"
          end
        end
      end

      return @participants[0]
    end

    private

    def participant_exists?(game_participant)
      File.readlines("results.txt").collect(&:chomp).include?(game_participant)
    end
  end

  class EnqueueParticipants
    def initialize(new_participants)
      @new_participants = new_participants
    end

    def enqueue
      @new_participants.each do |new_participant|
        ids = Scraper::SummonerMatches.new(new_participant).fetch_match_ids
        participants = Scraper::MatchParticipants.new(ids).generate_participants
      end
    end
  end
end

SUMMONER_INPUTTED = ARGV[0]
Scraper.new(SUMMONER_INPUTTED).work
