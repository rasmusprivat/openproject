module Mixins
  module ChangePasswordController
    protected

    # Change password using params resulting from the my/password view.
    # Used by account/force_password_change and my/password.
    def change_password(user)
      if request.post?
        if user.check_password?(params[:password])
          user.password, user.password_confirmation = params[:new_password], params[:new_password_confirmation]
          if user.valid?
            user.force_password_change = false
            if user.save
              flash[:notice] = l(:notice_account_password_updated)
              return true
            end
          end
        else
          flash[:error] = l(:notice_account_wrong_password)
        end
      end
      false
    end
  end
end
