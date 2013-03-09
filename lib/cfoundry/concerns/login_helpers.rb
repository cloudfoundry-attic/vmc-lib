require "base64"

module CFoundry
  module LoginHelpers
    def login_prompts
      if @base.uaa
        @base.uaa.prompts
      else
        {
          :username => ["text", "Email"],
          :password => ["password", "Password"]
        }
      end
    end

    def login(username, password)
      @base.token =
        if @base.uaa
          AuthToken.from_uaa_token_info(@base.uaa.authorize(username, password))
        else
          AuthToken.new(@base.create_token({:password => password}, username)[:token])
        end
    end
  end
end
