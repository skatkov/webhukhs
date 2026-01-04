class FailingWithExposedErrors < Webhukhs::BaseHandler
  def handle(_request)
    raise "oops"
  end

  def expose_errors_to_sender? = true
end
