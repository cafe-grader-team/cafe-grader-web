# Authentication and user imports through programming.in.th web request
require 'net/http'
require 'uri'
require 'json'

class ProgrammingAuthenticator
  PROGRAMMING_AUTHEN_URL = "https://programming.in.th/authen.php"

  def find_or_create_user(result)
    user = User.find_by(login: result['username'])
    if not user
      user = User.new(login: result['username'],
                      full_name: result['firstname'] + ' ' + result['surname'],
                      alias: result['display'],
                      email: result['email'])
      user.password = User.random_password
      user.save
    end
    return user
  end
  
  def authenticate(login, password)
    uri = URI(PROGRAMMING_AUTHEN_URL)
    result = Net::HTTP.post_form(uri, 'username' => login, 'password' => password)
    request_result = JSON.parse(result.body)

    if request_result.fetch('status', 'incorrect') == 'OK'
      return find_or_create_user(request_result)
    else
      return nil
    end
  end
end
