class String
  def col(width)
    self[0,width].ljust(width)
  end

  def rcol(width) #right justified
    self[0,width].rjust(width)
  end
end


