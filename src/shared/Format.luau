--[[
	Format.luau
	Number formatting shared by server and client: 1234 -> "1.23K",
	5600000 -> "5.6M". Small numbers are shown as-is.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function Format.Number(n: number): string
	n = math.floor(n)
	local negative = n < 0
	n = math.abs(n)

	if n < 1000 then
		return (if negative then "-" else "") .. tostring(n)
	end

	local index = 1
	local value = n
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end

	local text
	if value >= 100 then
		text = ("%d"):format(math.floor(value))
	elseif value >= 10 then
		text = ("%.1f"):format(math.floor(value * 10) / 10)
	else
		text = ("%.2f"):format(math.floor(value * 100) / 100)
	end
	-- trim trailing zeros: "1.50" -> "1.5", "2.00" -> "2"
	if text:find(".", 1, true) then
		text = (text:gsub("0+$", ""):gsub("%.$", ""))
	end

	return (if negative then "-" else "") .. text .. SUFFIXES[index]
end

return Format
