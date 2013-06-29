module Ripple
  module Encryption
    # Implements the {Riak::Serializer} API for the purpose of
    # encrypting/decrypting Ripple documents as JSON.
    #
    # Example usage:
    #     path = File.join(ROOT_DIR,'config','encryption.yml')
    #     
    #     ::Riak::Serializers['application/x-json-encrypted'] = Ripple::Encryption::JsonSerializer.new
    #     (
    #       OpenSSL::Cipher.new(config['cipher']), path
    #     )
    #
    #     class MyDocument
    #       include Ripple::Document
    #       include Ripple::Encryption
    #     end
    #
    # @see Encryption
    class JsonSerializer
      # @return [String] The Content-Type of the internal format,
      #      generally "application/json"
      attr_accessor :content_type

      # @return [OpenSSL::Cipher, OpenSSL::PKey::*] the cipher used to encrypt the object
      attr_accessor :cipher

      # Cipher-specific settings
      # @see OpenSSL::Cipher
      attr_accessor :key, :iv, :key_length, :padding

      # Creates a serializer using the provided cipher and internal
      # content type. Be sure to set the {#key}, {#iv}, {#key_length},
      # {#padding} as appropriate for the cipher before attempting
      # (de-)serialization.
      # @param [OpenSSL::Cipher] cipher the desired
      #     encryption/decryption algorithm
      # @param [String] path the File location of 'encryption.yml'
      #     private key file
      def initialize(cipher, path)
        @cipher, @content_type = cipher, 'application/x-json-encrypted'
        @config = Ripple::Encryption::Config.new(path)
      end

      # Serializes and encrypts the Ruby object using the assigned
      # cipher and Content-Type.
      # @param [Object] object the Ruby object to serialize/encrypt
      # @return [String] the serialized, encrypted form of the object
      def dump(object)
        JsonDocument.new(@config, object).encrypt
      end

      # Decrypts and deserializes the blob using the assigned cipher
      # and Content-Type.
      # @param [String] blob the original content from Riak
      # @return [Object] the decrypted and deserialized object
      def load(object)
        # try the v2 (0.0.2) compatible way of deserialize first
        begin
          return EncryptedJsonDocument.new(@config, object).decrypt
        # if that doesn't work, try the v1 (0.0.1) way
        rescue OpenSSL::Cipher::CipherError, MultiJson::DecodeError
          internal = decrypt(object)
          return ::Riak::Serializers.deserialize('application/json', internal)
        end
      end

      private

      # generates a new iv each call unless a static (less secure)
      # iv is used.
      def encrypt(object)
        old_version = '0.0.1'
        result = ''
        if cipher.respond_to?(:iv=) and @iv == nil
          iv = OpenSSL::Random.random_bytes(cipher.iv_len)
          cipher.iv = iv
          result << old_version << iv
        end

        if cipher.respond_to?(:public_encrypt)
          result << cipher.public_encrypt(object)
        else
          cipher_setup :encrypt
          result << cipher.update(object) << cipher.final
          cipher.reset
        end
        return result
      end

      def decrypt(cipher_text)
        old_version = '0.0.1'

        if cipher.respond_to?(:iv=) and @iv == nil
          version = cipher_text.slice(0, old_version.length)
          cipher.iv = cipher_text.slice(old_version.length, cipher.iv_len)
          cipher_text = cipher_text.slice(old_version.length + cipher.iv_len, cipher_text.length)
        end

        if cipher.respond_to?(:private_decrypt)
          cipher.private_decrypt(cipher_text)
        else
          cipher_setup :decrypt
          result = cipher.update(cipher_text) << cipher.final
          cipher.reset
          result
        end
      end

      def cipher_setup(mode)
        cipher.send mode
        cipher.key        = key        if key
        cipher.iv         = iv         if iv
        cipher.key_length = key_length if key_length
        cipher.padding    = padding    if padding
      end
    end
  end
end
