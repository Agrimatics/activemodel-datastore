class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  ##
  # This could be the id of an Account, Company, etc.
  #
  def fake_ancestor
    12345
  end
end
