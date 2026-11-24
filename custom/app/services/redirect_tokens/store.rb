class RedirectTokens::Store
  KEY = 'REDIRECT_TOKEN::%<token>s'.freeze

  def self.write(token, payload, ttl_seconds)
    ::Redis::Alfred.setex(key(token), JSON.generate(payload), ttl_seconds)
  end

  def self.consume(token)
    return if token.blank?

    claimed = ::Redis::Alfred.set(claim_key(token), '1', nx: true, ex: 60)
    return unless claimed

    raw = ::Redis::Alfred.get(key(token))
    ::Redis::Alfred.delete(key(token))
    return if raw.blank?

    JSON.parse(raw)
  end

  def self.ttl(token)
    ::Redis::Alfred.ttl(key(token))
  end

  def self.exists?(token)
    ::Redis::Alfred.exists?(key(token))
  end

  def self.count
    ::Redis::Alfred.keys_count('REDIRECT_TOKEN::*')
  end

  def self.key(token)
    format(KEY, token: token)
  end

  def self.claim_key(token)
    "#{key(token)}::claim"
  end
end
