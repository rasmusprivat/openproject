class UserPassword < ActiveRecord::Base
  belongs_to :user, :inverse_of => :passwords

  # passwords must never be modified, so doing this on create should be enough
  before_create :salt_and_hash_password!

  attr_accessor :plain_password

  # Checks whether the stored password is the same as a given plaintext password
  def same_as_plain_password?(plain_password)
    UserPassword.secure_compare(UserPassword.hash_with_salt(plain_password,
                                                            self.salt),
                                self.hashed_password)
  end

  # Returns a 128bits random salt as a hex string (32 chars long)
  def self.generate_salt
    SecureRandom.hex(16)
  end

  # Return password digest
  def self.hash_password(plain_password)
    Digest::SHA1.hexdigest(plain_password)
  end

  # Hash a plaintext password with a given salt
  # The hashed password has following form: SHA1(salt + SHA1(password))
  def self.hash_with_salt(plain_password, salt)
    # We should really use a standard key-derivation function like bcrypt here
    hash_password("#{salt}#{hash_password plain_password}")
  end

  # constant-time comparison algorithm to prevent timing attacks
  def self.secure_compare(a, b)
    return false if a.blank? || b.blank? || a.bytesize != b.bytesize
    l = a.unpack "C#{a.bytesize}"

    res = 0
    b.each_byte { |byte| res |= byte ^ l.shift }
    res == 0
  end

  private

  def salt_and_hash_password!
    return if self.plain_password.nil?
    self.salt = UserPassword.generate_salt
    self.hashed_password = UserPassword.hash_with_salt(self.plain_password,
                                                       salt)
  end
end
