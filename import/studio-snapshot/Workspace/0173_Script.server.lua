function Active()
   if game.Lighting.TimeOfDay == "18:00:00" then
	wait(math.random(10))
      script.Parent.Light.SpotLight.Enabled = true
      script.Parent.Light.SpotLight.Color = Color3.new(178/255, 255/255, 207/255)
      script.Parent.Light.Lamp.Enabled = true
      script.Parent.Light.Lamp.ImageLabel.ImageColor3 = Color3.new(178/255, 255/255, 207/225)
      wait(10)
      script.Parent.Light.SpotLight.Color = Color3.new(178/255, 255/255, 207/225)
      script.Parent.Light.Lamp.ImageLabel.ImageColor3 = Color3.new(178/255, 255/255, 207/225)
   elseif game.Lighting.TimeOfDay == "06:00:00" then
	wait(math.random(10))
      script.Parent.Light.SpotLight.Enabled = false
      script.Parent.Light.Lamp.Enabled = false
   end
end
game.Lighting.Changed:connect(Active)