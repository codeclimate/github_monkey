# Use the Marsaglia polar method
# to generate a random number within a range
# It treats the given range as one half of a normal distribution mean at
# range.first and 2 stddev at range.last to generate the random number, then
# adjusts it so the range is actually being treated kinda like a chi
# distribution (effectively just 1 half of the normal distribution).
#
# https://en.wikipedia.org/wiki/Marsaglia_polar_method
module RandomGaussian
  def self.from_range(range)
    mean = range.first
    stddev = (range.last - mean).to_f / 2.0

    u, v, s = 0, 0, 0
    loop do
      u = rand() * 2 - 1
      v = rand() * 2 - 1
      s = (u * u) + (v * v)
      break if s < 1 && s > 0
    end

    mul = Math.sqrt(-2 * Math.log(s) / s)
    val = (mean + stddev * u * mul).round
    if val < mean
      val = mean + (mean - val)
    end
    val
  end
end
