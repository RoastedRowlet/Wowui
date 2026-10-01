local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Hunter-Marksmanship','Paladin-Holy','Hunter-BeastMastery','Shaman-Restoration','Mage-Arcane','Unknown-Unknown','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Druid-Guardian','Priest-Holy','Paladin-Retribution','DeathKnight-Frost','Evoker-Devastation','Evoker-Preservation','DemonHunter-Vengeance','Priest-Shadow','DemonHunter-Havoc','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Evoker-Augmentation','Mage-Frost','Druid-Balance','Druid-Feral','Druid-Restoration','Warrior-Protection','Monk-Mistweaver','Rogue-Assassination','Priest-Discipline','Warrior-Arms',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acidsword:BAAANQAECgQIBAABNQAECgkJLgABACkdAA==.',
Ad='Adaria:BAAANQADCgMIAwAAAA==.Adder:BAAANQADCgIIAgAAAA==.Adelgeise:BAAANQADCggJEgABNQAECgkJIgACADkiAA==.Adrua:BAAANQADCgUIBwAAAA==.Adym:BAABNQAECoEcAAIDAAgKIxE2VAAkAgADAAgKIxE2VAAkAgAAAA==.',
Ag='Agave:BAABNQAECoEbAAIEAAgKEg9cVwC3AQAEAAgKEg9cVwC3AQAAAA==.',
Ai='Aiyah:BAAANQAECgQICAAAAA==.',
Al='Altarboi:BAAANQAECgQIBAAAAA==.Alüçard:BAAANQAECgQIEAAAAA==.',
Am='Amoraniel:BAABNQAECoEhAAIFAAgKHR4OVQCtAgAFAAgKHR4OVQCtAgAAAA==.',
An='Anavar:BAAANQAECgYIBgAAAA==.Andrar:BAAANQADCgYIBwAAAA==.Andres:BAAANQAFFAEIAQAAAA==.Andresra:BAABNQAECoEkAAIFAAgK0CDoQADiAgAFAAgK0CDoQADiAgABNQAFFAEIAQAGAAAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAAANQAECgQIDQAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.',
As='Asrael:BAAANQADCgYIBgABNQAECggIGQAHAFgTAA==.Asterin:BAAANQADCgUICwAAAA==.',
Au='Augtism:BAAANQADCgMIAwABNQAECgcIDgAGAAAAAA==.',
Av='Avâtre:BAAANQAECgUICgAAAA==.',
Ba='Baguette:BAAANQAECgUIDAAAAA==.Bajingobomb:BAABNQAECoEaAAMIAAcKSiAXJgBVAgAIAAcKxx8XJgBVAgAJAAYKtx11OADlAQAAAA==.Bakblood:BAAANQABCgYICAAAAA==.Bakshung:BAAANQADCgYIBgAAAA==.Barkruffalo:BAAANQADCgEJAQAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.Barnpall:BAAANQAECgYIBgAAAA==.Barrybonds:BAAANQADCggIDAAAAA==.Bayao:BAAANQAECgUIBQAAAA==.',
Be='Be:BAAANQAECgYIEgAAAA==.Beckyoncé:BAABNQAECoEbAAIKAAgK/x/0DQDnAgAKAAgK/x/0DQDnAgAAAA==.Bedris:BAAANQAECgUIDQAAAA==.Beerticus:BAABNQAECoEUAAILAAYKGRu9IADLAQALAAYKGRu9IADLAQAAAA==.',
Bi='Biar:BAAANQADCgEIAQAAAA==.Bigdingus:BAABNQAECoEXAAIMAAgKzRsBCQB6AgAMAAgKzRsBCQB6AgAAAA==.Binggles:BAACNQAFFIEdAAIFAAcKGSHWAADXAgAFAAcKGSHWAADXAgA1AAQKgR8AAgUACQqWJTYTAHcDAAUACQqWJTYTAHcDAAAA.',
Bl='Blacksheep:BAAANQAECgIIAgAAAA==.Blôôðhôôf:BAAANQADCgQIBAABNQAECgUICgAGAAAAAA==.',
Bo='Bokinar:BAAANQAECggICAAAAA==.Bomboclaat:BAAANQAECgIIBgABNQAECggIGgALABokAA==.Boolay:BAAANQAECgUIDAABNQABCgUIBQAGAAAAAA==.Boomcommand:BAAANQADCgEIAgAAAA==.Boosteyboy:BAAANQAECgUIBQAAAA==.Boozing:BAAANQADCgMIAwABNQAECggIHAADAAIiAA==.Bosmina:BAABNQAECoEnAAINAAkK3BnUJACeAgANAAkK3BnUJACeAgAAAA==.',
Br='Braei:BAAANQAECgYIDgAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Brenhunt:BAAANQADCgYIBgAAAA==.Brenmonk:BAAANQAECgUIDgAAAA==.Brenpriest:BAAANQADCgYIBgAAAA==.Brenshammy:BAAANQADCgUIBQAAAA==.Bruenor:BAAANQADCgYIBgAAAA==.',
Bu='Bubblebaddie:BAAANQAECgMIBQAAAA==.Bubblicous:BAAANQADCgYIBgAAAA==.Bugenhagen:BAABNQAECoEnAAIEAAkKbCQCBACWAwAEAAkKbCQCBACWAwAAAA==.Butchers:BAAANQADCgUIBwAAAA==.Buttpaladin:BAABNQAECoEdAAIOAAgKFhgAXwAlAgAOAAgKFhgAXwAlAgAAAA==.',
Ca='Caliden:BAAANQABCgYICwAAAA==.Cardib:BAACNQAFFIELAAMIAAUKEh+5AwCcAQAIAAUKEh+5AwCcAQAPAAEKEhHREgBQAAA1AAQKgR4AAwgACQqpJPkMACkDAAgACQo/JPkMACkDAA8AAQrAHFF4AFAAAAAA.Cavos:BAABNQAECoEdAAIKAAcKlxu3HAA2AgAKAAcKlxu3HAA2AgAAAA==.',
Ce='Centradin:BAAANQAECgIIBAAAAA==.Cernsarn:BAAANQAECgcIEwAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Chiri:BAEBNQAECoEcAAMQAAkK2Q/KEQD4AQAQAAkK2Q/KEQD4AQARAAMKEgNrOQB/AAAAAA==.Chvngus:BAABNQAECoEdAAIOAAgKIyDhNgCvAgAOAAgKIyDhNgCvAgAAAA==.',
Ci='Citizencain:BAAANQAECgQICwAAAA==.',
Cl='Claytnbigsby:BAAANQAECgMIBwAAAA==.',
Co='Cocheeze:BAAANQADCgYICgAAAA==.Cogswell:BAAANQADCggIEgAAAA==.Condor:BAEANQAECggICwAAAA==.Coohwhip:BAAANQAECgEIAQAAAA==.Cornorgan:BAAANQAECgcIDAAAAA==.Cowbut:BAAANQADCgEIAQAAAA==.',
Cr='Crakidos:BAAANQADCgQJBAAAAA==.Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAAANQAECgcIDgAAAA==.Cristobal:BAAANQAECgUIBAAAAA==.Crunkshot:BAAANQADCgMIBAAAAA==.',
Cy='Cydea:BAAANQAECgMIBAAAAA==.',
Da='Dagidan:BAABNQAECoEkAAISAAkKWhEFCQABAgASAAkKWhEFCQABAgAAAA==.Darktide:BAAANQAECggICAAAAA==.Dashel:BAAANQAECgIIAgABNQAECggIGwATAKgPAA==.',
De='Dead:BAAANQADCggICAAAAA==.Deathtoxi:BAAANQAECgEIAQAAAA==.Demontotems:BAAANQADCgYIBgAAAA==.Demotoxi:BAABNQAECoEWAAQKAAcKvBkKHgAnAgAKAAcKHxkKHgAnAgAUAAQKZhfUSgD/AAASAAIKzQrxIABVAAAAAA==.Deriso:BAAANQAECgcIDQAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCggIDAAGAAAAAA==.Destrozinth:BAAANQAECgcICwAAAA==.Dethorok:BAABNQAECoEdAAIDAAkKeyF9CgBpAwADAAkKeyF9CgBpAwAAAA==.Deuce:BAAANQABCgIJAQAAAA==.Deåth:BAAANQADCgYIDQABNQAECgEIAQAGAAAAAA==.',
Di='Diagonpally:BAAANQADCgYIDgABNQAECgkJJwAEAGwkAA==.Dib:BAAANQAECgQIBAAAAA==.Digey:BAAANQAECgYIDgAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAAANQAECgYIDgAAAA==.',
Do='Dontlookatme:BAAANQABCgUIBQAAAA==.Dopeaf:BAAANQADCgcIDAAAAA==.Dottër:BAAANQADCggIEwABNQAECgEIAQAGAAAAAA==.',
Dr='Drakbek:BAAANQAECgMIBAAAAA==.Dreadshot:BAAANQADCgYIBgAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dronebot:BAABNQAECoE1AAITAAgKXBxFEgCeAgATAAgKXBxFEgCeAgAAAA==.Drucifer:BAAANQADCggIDwAAAA==.',
Du='Durros:BAAANQAECgYICQAAAA==.Dustyshotz:BAAANQADCgUIBQAAAA==.',
Eb='Eboger:BAAANQAECgIIAgAAAA==.',
El='Elunelphie:BAAANQADCgUIBQAAAA==.',
Em='Embody:BAAANQAECgUIDQAAAA==.Emiree:BAAANQAECgIIAgAAAA==.',
En='Endlyss:BAABNQAECoEYAAIOAAgKvhczVwA+AgAOAAgKvhczVwA+AgAAAA==.',
Er='Erasmas:BAABNQAECoEiAAMCAAkKOSKdBQCLAwACAAkKOSKdBQCLAwAOAAYKlRqXfQDMAQAAAA==.Erzascarlét:BAABNQAECoEnAAIHAAkKlB3VCADYAgAHAAkKlB3VCADYAgAAAA==.',
Es='Essentia:BAAANQABCgEIAQAAAA==.',
Eu='Euphoricx:BAAANQAECgYICwAAAA==.',
Ev='Evildeader:BAAANQADCggIHgABNQAECgQIBgAGAAAAAA==.Eviltotems:BAAANQAECgQIBgAAAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAABNQAECoEhAAMVAAkKzxxuKACkAgAVAAgKKB1uKACkAgAEAAIKQAtgzgB0AAAAAA==.Fantasma:BAAANQADCgYIFQAAAA==.',
Fe='Fear:BAAANQAECgIIAgAAAA==.',
Fi='Findal:BAAANQADCggICQABNQABCgIIAgAGAAAAAA==.Fistymoo:BAEANQADCgMIAwABNQAECgkJHAAQANkPAA==.Fivemagics:BAABNQAECoEXAAMWAAgKohMUdgCkAQAWAAYKMxQUdgCkAQAXAAIK7RGqTwB6AAAAAA==.',
Fl='Fleaboy:BAAANQAECgcIDgAAAA==.Flist:BAABNQAECoEaAAILAAgKGiQjBwA7AwALAAgKGiQjBwA7AwAAAA==.Floof:BAAANQADCgYIDwAAAA==.',
Fo='Foe:BAAANQAECgUICQAAAA==.Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAAANQAECgUIDQAAAA==.Freesia:BAAANQADCggIFQAAAA==.Fruitjuice:BAAANQAECgIIAgAAAA==.',
Fx='Fxce:BAAANQAECgUIEAAAAA==.',
['Fâ']='Fâmine:BAAANQADCggICAAAAA==.',
Ga='Gaothan:BAAANQAECgEJAQAAAA==.',
Ge='Genjy:BAAANQABCgIIAgAAAA==.',
Gh='Ghulz:BAAANQAECgcIEgAAAA==.',
Gi='Gibsmedats:BAABNQAECoEZAAIUAAcK5w7TNACkAQAUAAcK5w7TNACkAQAAAA==.',
Gl='Glaiven:BAABNQAECoEbAAIKAAgKGBLuIAAJAgAKAAgKGBLuIAAJAgAAAA==.Glasscleaner:BAAANQAECgcIDwABNQAFFAUICQARACMXAA==.Glenmorangie:BAAANQAECggIEQAAAA==.',
Gn='Gnartusk:BAAANQAECgYIEQAAAA==.',
Go='Goober:BAAANQADCgEIAQABNQAECgIIAgAGAAAAAA==.',
Gr='Greens:BAAANQAECgcIDwAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Gremory:BAAANQADCgYJCwABNQADCggIDAAGAAAAAA==.Grillvy:BAAANQADCgIIBgAAAA==.Grumbo:BAAANQAECgEIAQABNQAECgQIBAAGAAAAAA==.Grïma:BAABNQAECoEmAAIYAAgKsBzGAgCxAgAYAAgKsBzGAgCxAgAAAA==.',
Gs='Gsus:BAAANQADCggICAABNQAECggIHAAZAEIZAA==.',
Gu='Gueritestje:BAAANQAECgUIEwAAAA==.Guzzlord:BAABNQAECoEcAAQRAAgKPAvKIwBbAQARAAcKkQnKIwBbAQAQAAQKQQZUJgC7AAAaAAQKegjOEgCtAAAAAA==.',
Ha='Halfman:BAAANQAECgEIAQAAAA==.Handsomejack:BAAANQAECgEIAQABNQAECgcIGgAIAEogAA==.Hanekawa:BAAANQAECgEIAQABNQAECggIIwATAD4hAA==.Harfnar:BAAANQABCggICAABNQADCgEIAQAGAAAAAA==.',
Hb='Hboozing:BAABNQAECoEcAAMDAAgKAiJ6FQAZAwADAAgKAiJ6FQAZAwABAAEKkxL6ZABAAAAAAA==.',
He='Healyhavok:BAAANQADCgIIAgAAAA==.Heayt:BAAANQABCgIIBAAAAA==.Heleous:BAAANQADCgMIAwABNQADCgYIBgAGAAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Hipdrop:BAAANQAECgMIAwAAAA==.Hitoshura:BAAANQAECgUIDAAAAA==.',
Ho='Holyginger:BAAANQAECgIIBQAAAA==.Holyglizzy:BAAANQAECgcIEgAAAA==.Holymajìk:BAAANQABCgIIAwAAAA==.',
Hy='Hypérîon:BAAANQAECgQIBQAAAA==.',
Ia='Iagging:BAAANQAECgcJEgABNQAFFAUICQARACMXAA==.',
Ik='Ikiryo:BAEANQAECgIIBQAAAA==.',
Im='Imtuggdup:BAABNQAECoEZAAMFAAkK3xxUOAD6AgAFAAkK3xxUOAD6AgAbAAEKPhiHNgA7AAAAAA==.Imzachedup:BAAANQADCgYICAAAAA==.',
In='Infidel:BAABNQAECoEmAAIcAAkKAyStBACmAwAcAAkKAyStBACmAwAAAA==.Invert:BAAANQADCgUJBQAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgEIAwAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQAAAA==.',
Ir='Irisharcher:BAAANQAECgEIAQAAAA==.Irishman:BAAANQADCggJGAAAAA==.',
It='Itazki:BAABNQAECoEWAAMdAAgK3B2WBQDOAgAdAAgK3B2WBQDOAgAcAAEKHQzGkwAwAAAAAA==.',
Ja='Jackpot:BAAANQADCgEIAQAAAA==.Jaft:BAAANQADCgUICgAAAA==.Jalter:BAACNQAFFIEJAAIRAAUKIxd5BQDEAQARAAUKIxd5BQDEAQA1AAQKgRoAAhEACQrbIR0EAF0DABEACQrbIR0EAF0DAAAA.',
Je='Jediknight:BAAANQAECgMIBAAAAA==.Jenga:BAAANQAECgcIDAAAAA==.Jergal:BAAANQAECgcIEAAAAA==.Jertdor:BAAANQADCgQIBAAAAA==.',
Jf='Jf:BAABNQAECoEmAAMOAAgKNBfUVgA/AgAOAAgKNBfUVgA/AgACAAgK2QmKYACpAQAAAA==.',
Ji='Jinkala:BAAANQABCgYIBwAAAA==.Jitzakkal:BAACNQAFFIESAAMXAAYKhyVjAgDoAAAWAAQK9CSXBQC6AQAXAAIKrCZjAgDoAAA1AAQKgSEAAxcACQoSJiMJAFgCABYABwqtJfggAM0CABcABgpkJCMJAFgCAAAA.',
Jn='Jn:BAAANQADCgcIDAAAAA==.',
Jo='Johnpaladin:BAABNQAECoEhAAIOAAgKdyXdEABnAwAOAAgKdyXdEABnAwAAAA==.Joshswims:BAAANQAECgUICQAAAA==.',
Js='Js:BAAANQADCgYICgAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECgkJJwAFAN0jAA==.Juleita:BAAANQABCgQIBAAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kapena:BAAANQAECggIDQAAAA==.Kardinal:BAABNQAECoEmAAQWAAkKmiLQBACRAwAWAAkKmiLQBACRAwAXAAUK9xsIHAB+AQAYAAEKwRveIQBFAAAAAA==.Kargan:BAAANQADCgcICAABNQAECgQIBAAGAAAAAA==.Karliee:BAAANQADCggICAABNQADCggIFQAGAAAAAA==.Karpathous:BAAANQAECggIBAAAAA==.',
Ke='Keladorn:BAAANQAECgUIDgAAAA==.',
Kh='Khanyiso:BAABNQAECoEZAAIHAAgKWBNKGQDTAQAHAAgKWBNKGQDTAQAAAA==.Kharak:BAAANQAECgYIEwABNQABCgIIAgAGAAAAAA==.',
Ki='Kichii:BAAANQAECgMIAwAAAA==.Kieran:BAABNQAECoEbAAMTAAgKqA/yMQBAAQATAAYKwAvyMQBAAQANAAMK0gNHrACXAAAAAA==.Kilsaurys:BAABNQAECoEjAAQcAAkKIhtAGwC/AgAcAAkKIhtAGwC/AgAeAAcKrxIMIADQAQAMAAUKugw9JQDfAAAAAA==.Kirakishou:BAAANQAECgEIAQABNQAECggIIwATAD4hAA==.Kismete:BAAANQAECgcIEAAAAA==.',
Ko='Konstantine:BAAANQAECgUIDAAAAA==.',
Kr='Krittykitkat:BAAANQAECgIIAgABNQAECgYIBgAGAAAAAA==.Kryptocron:BAAANQAECgMIAwAAAA==.',
Kw='Kwazlock:BAAANQADCgEIAQAAAA==.',
Ky='Kysoti:BAAANQADCgQIBAAAAA==.',
['Kí']='Kítsune:BAAANQADCggIIwAAAA==.',
La='Laprimera:BAAANQADCggIHAAAAA==.Lasticon:BAAANQAECgcIDAABNQAECggICAAGAAAAAA==.Lazyjade:BAABNQAECoEaAAITAAkKEBeiEwCKAgATAAkKEBeiEwCKAgAAAA==.',
Le='Lenarius:BAAANQABCgUJBQABNQABCgYIBgAGAAAAAA==.Leonidass:BAAANQADCgUIBQAAAA==.Leyline:BAAANQADCgYICwAAAA==.',
Li='Lichborne:BAAANQADCgcIBwAAAA==.Lilgangster:BAAANQADCgIIAgAAAA==.',
Lo='Lockofdirish:BAAANQADCgYICwAAAA==.Lorfirandor:BAAANQADCgYICwAAAA==.Lorynn:BAAANQAECggIEgAAAA==.',
Ma='Madwe:BAAANQAECgcICQAAAA==.Magturri:BAABNQAECoEaAAMDAAcKpho1SwA/AgADAAcKpho1SwA/AgABAAIKQAeGXgBdAAAAAA==.Majìkstik:BAAANQABCgIIAgAAAA==.Mamameatmode:BAAANQAECgUIBwAAAA==.Marlbororeds:BAAANQAECgYICgAAAA==.Maxfirepower:BAAANQADCgYIEQAAAA==.Maxfrogpower:BAAANQADCgcIDAAAAA==.Maxsunward:BAAANQAECgMIBQAAAA==.',
Me='Meepasaurus:BAABNQAECoEkAAIfAAgKQyBiBQDgAgAfAAgKQyBiBQDgAgAAAA==.Megaforce:BAAANQAECgEIAQAAAA==.Mellky:BAABNQAECoEmAAIgAAgKPSXXAwBNAwAgAAgKPSXXAwBNAwAAAA==.Metanoia:BAABNQAECoEUAAIhAAYKvR/fJAD/AQAhAAYKvR/fJAD/AQABNQAECgkJJgAWAJoiAA==.',
Mg='Mgamer:BAAANQADCgYIBgAAAA==.',
Mi='Mib:BAEANQAECggIDAABNQAECggICwAGAAAAAA==.Mibb:BAEBNQAECoEgAAIFAAkKzx9iLQAZAwAFAAkKzx9iLQAZAwABNQAECggICwAGAAAAAA==.Midnitetrvlr:BAABNQAECoEXAAIIAAcKhQuvVABYAQAIAAcKhQuvVABYAQAAAA==.Migothedruid:BAAANQADCgEIAQAAAA==.Mirren:BAABNQAECoEcAAIbAAgK1xYeBwA3AgAbAAgK1xYeBwA3AgAAAA==.Missmoans:BAAANQADCgYICAABNQAECgYIEAAGAAAAAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Momojojo:BAABNQAECoEcAAIXAAcKHyBOBgCYAgAXAAcKHyBOBgCYAgAAAA==.Monre:BAAANQAECgMIBQABNQAECgcIDAAGAAAAAA==.Moonflame:BAABNQAECoEaAAINAAkKzhrJIwCkAgANAAkKzhrJIwCkAgAAAA==.Mooriah:BAAANQAECgUIEgAAAA==.Mordekhuul:BAABNQAECoEZAAIWAAkKeBiTJQC5AgAWAAkKeBiTJQC5AgAAAA==.Motowa:BAAANQAECgIIAgAAAA==.',
Mp='Mpkshaman:BAAANQAECgcIDgAAAA==.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynche:BAAANQADCgYJBgABNQAECgQIBwAGAAAAAA==.Mynchus:BAAANQAECgQIBwAAAA==.Mysterydh:BAAANQAECgYIBwAAAA==.Mysterypala:BAAANQAECgUJCgAAAA==.Mysteryvoke:BAAANQAECgUIDQAAAA==.',
Na='Naneko:BAAANQAECgUIDAAAAA==.',
Ne='Neelix:BAAANQAECgUIDQAAAA==.Nehi:BAAANQAECggICQAAAA==.Neotahr:BAABNQAECoEkAAIBAAkKSw4hIAAPAgABAAkKSw4hIAAPAgAAAA==.Neuron:BAEANQABCgUICgABNQAECgIIBQAGAAAAAA==.',
Ni='Nickiminajj:BAAANQAECggICAAAAA==.Nismoto:BAABNQAECoElAAIDAAgK/BBGVwAbAgADAAgK/BBGVwAbAgAAAA==.Nitehunter:BAAANQAECgYICwAAAA==.',
No='Noobert:BAAANQAECgEIAQAAAA==.Novademic:BAAANQAECgUICwAAAA==.',
['Nö']='Növacaïn:BAAANQAECgEIAQAAAA==.',
Og='Ognikkay:BAABNQAECoElAAIdAAgKlx/uBADoAgAdAAgKlx/uBADoAgAAAA==.',
Or='Oranthør:BAAANQADCgUIBQAAAA==.',
Oy='Oyea:BAAANQABCgIIAgABNQAECgkJGgATABAXAA==.',
Pa='Pabiloneta:BAAANQAECgMIAwABNQAFFAEIAQAGAAAAAA==.Pakami:BAAANQAECgQIBAAAAA==.Pallyana:BAABNQAECoEcAAIOAAkKPRmcOgCfAgAOAAkKPRmcOgCfAgAAAA==.Palosdin:BAAANQAECgIIAgAAAA==.Papapump:BAAANQADCgQJBAAAAA==.Parsleyposh:BAAANQADCgcICgABNQAECgQIBAAGAAAAAA==.Pass:BAAANQADCgIIAgABNQAECggIGgALABokAA==.',
Pe='Perridan:BAAANQADCggIFAAAAA==.',
Pi='Pinkponyclub:BAABNQAECoEbAAICAAgKsRjBLwBsAgACAAgKsRjBLwBsAgAAAA==.Pinkyshock:BAABNQAECoE0AAIHAAgKMx0JDgBxAgAHAAgKMx0JDgBxAgAAAA==.Pista:BAAANQADCgIIAQAAAA==.',
Po='Pog:BAAANQAECgIIAgABNQAECgQICAAGAAAAAA==.Portholes:BAAANQAECgUIBQAAAA==.',
Pr='Praystatiøn:BAAANQADCgYICgAAAA==.',
Ps='Psyop:BAAANQAECgQIDQABNQAECgkJJgANAEQhAA==.',
Pu='Punked:BAAANQADCgYIBgAAAA==.Purplepain:BAAANQAECgYICwABNQAFFAUICgALAMQaAA==.Purplod:BAABNQAECoEcAAMPAAgKggqQNgCPAQAPAAgKggqQNgCPAQAJAAUKxgUuewC+AAAAAA==.',
Py='Pyatpree:BAAANQADCgcIDgAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
Qi='Qing:BAABNQAECoEcAAIZAAgKQhmyCQBDAgAZAAgKQhmyCQBDAgAAAA==.',
Qy='Qybxboogies:BAAANQAECgYICwAAAA==.Qybxboogyy:BAAANQADCgIIAgAAAA==.',
Ra='Raensong:BAAANQAECgIJAgAAAA==.Rafterman:BAAANQAECgQIBAAAAA==.Rainingarrow:BAAANQABCgIIAwAAAA==.Raisa:BAABNQAECoEdAAMWAAkKAR31NAB7AgAWAAcK7x/1NAB7AgAXAAMK7hdeMQDrAAAAAA==.Rakarum:BAAANQAECgEIAQAAAA==.Rasar:BAAANQAECgYJDwAAAA==.Rathew:BAAANQAECgYJEAAAAA==.Rawnext:BAAANQAECgYJDQAAAA==.',
Re='Revenger:BAAANQABCgMIAgAAAA==.Revoker:BAABNQAECoEuAAMDAAgKtxM4SwA/AgADAAgKvBI4SwA/AgABAAcKuguTMABtAQAAAA==.',
Rh='Rhidge:BAAANQADCgYIBgAAAA==.',
Ri='Riddlez:BAABNQAECoEmAAMNAAgK9iXsBgBwAwANAAgK9iXsBgBwAwAiAAUKsCKZBgDnAQAAAA==.Riott:BAAANQABCgQIAwAAAA==.',
Ro='Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECgUIBwAAAA==.Rox:BAAANQAECgQJBwAAAA==.Royal:BAAANQADCgUIBQAAAA==.Royle:BAAANQAECgEIAQAAAA==.Roysham:BAAANQAECgQIBAAAAA==.Roywar:BAAANQAECgEIAQAAAA==.',
['Ré']='Réîgn:BAAANQAECgYIEgAAAA==.',
Sa='Sacrus:BAAANQAECgQIBAAAAA==.Samael:BAAANQADCgYIBgAAAA==.Sarah:BAABNQAECoEYAAMBAAkKcyJvDADxAgABAAkKcyJvDADxAgADAAEKcxAfEQFBAAAAAA==.',
Sc='Scalelord:BAAANQADCgYJCwABNQADCggIDAAGAAAAAA==.Scoobear:BAAANQAECgMIBgABNQAECgcIEgAGAAAAAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senisia:BAAANQADCgUIBQAAAA==.Senjougahara:BAACNQAFFIENAAIPAAUKoxtoAgC3AQAPAAUKoxtoAgC3AQA1AAQKgSoAAg8ACQreIzUHAEwDAA8ACQreIzUHAEwDAAAA.Seriyah:BAABNQAECoEdAAIdAAkKxxftBgCXAgAdAAkKxxftBgCXAgAAAA==.Serph:BAAANQAECgUIAwABNQAECgYIEAAGAAAAAA==.',
Sh='Shabane:BAAANQAECgYIEQAAAA==.Shame:BAABNQAECoEkAAITAAkKZhfCEgCXAgATAAkKZhfCEgCXAgAAAA==.Shankey:BAAANQADCgYIBgAAAA==.Shasta:BAAANQADCgQIBAAAAA==.Shinobi:BAAANQAECgUIDQAAAA==.Shirls:BAABNQAECoEbAAICAAgKCRmbMgBfAgACAAgKCRmbMgBfAgAAAA==.Shivak:BAABNQAECoEkAAIaAAkKwhLHBQAyAgAaAAkKwhLHBQAyAgAAAA==.Shivanie:BAAANQAECgQICQAAAA==.Shock:BAAANQAECgQICQAAAA==.Shredderella:BAABNQAECoEcAAIhAAgKkx6hEwCWAgAhAAgKkx6hEwCWAgAAAA==.Shrug:BAABNQAECoEbAAIjAAgKzBdKVwBBAgAjAAgKzBdKVwBBAgAAAA==.Shubie:BAAANQABCgIIAgABNQADCgUICwAGAAAAAA==.',
Si='Sicwiddit:BAAANQAECgQIBAAAAA==.',
Sk='Skeeda:BAAANQAECgEIAgAAAA==.Skylinex:BAAANQAECggIEwAAAA==.Skylinez:BAAANQAECgIIAgAAAA==.Skïttles:BAAANQAECgYIEAAAAA==.',
Sl='Sleezball:BAAANQAECgUJDAAAAA==.',
So='Softie:BAAANQAECgEIAQABNQAECgkJGQAjAHwXAA==.Sonictide:BAAANQAECgUICAAAAA==.Soulscream:BAABNQAECoEZAAINAAkKnhx2FQD4AgANAAkKnhx2FQD4AgAAAA==.',
Sp='Spaghetto:BAABNQAECoEdAAIcAAgKxhoVIgCGAgAcAAgKxhoVIgCGAgAAAA==.Sprite:BAAANQADCgQJBAAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgcIDwAAAA==.Strive:BAAANQADCgIIAgAAAA==.Stumpchuggns:BAAANQAECgEIAQAAAA==.',
Su='Suzel:BAAANQADCggIEgAAAA==.',
Sy='Sydaria:BAAANQABCgEJAQAAAA==.Synder:BAABNQAECoEbAAIaAAgKiwTkDAAmAQAaAAgKiwTkDAAmAQAAAA==.',
Ta='Tainin:BAAANQAECgYIEQAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQAECgEIAQAAAA==.Tarynna:BAAANQAECgYIEQAAAA==.Tazdingobomb:BAAANQAECgEIAQAAAA==.Tazerface:BAAANQAECgYIDgAAAA==.',
Te='Tekin:BAABNQAECoEaAAICAAcKZxUCUQDiAQACAAcKZxUCUQDiAQAAAA==.Teleprompter:BAAANQAECgQIBAAAAA==.Telrissan:BAAANQAECgYIDQAAAA==.Tenkawnor:BAAANQADCgcIBwAAAA==.Tenyroldemon:BAAANQAECgUIEQAAAA==.',
Th='Thald:BAABNQAECoEaAAIZAAcKQBceDgDOAQAZAAcKQBceDgDOAQAAAA==.Thaznotmilk:BAAANQADCgQIBAAAAA==.',
Ti='Timzilla:BAAANQADCgcIBwABNQAECggIIwAJAF8hAA==.Tinytip:BAAANQADCgYIBgAAAA==.Tisakna:BAABNQAECoEnAAMFAAkK3SOFQgDeAgAFAAgK2yKFQgDeAgAbAAMKESMMFAAnAQAAAA==.',
To='Togon:BAAANQAECggIAQAAAA==.Tooezy:BAAANQAECgEIAQAAAA==.Tool:BAAANQAECgIIAgAAAA==.Tostitos:BAAANQADCggICwAAAA==.',
Tr='Tralgina:BAAANQAECgYICQABNQAECgkJKgAHAGEbAA==.Trask:BAABNQAECoEcAAIFAAgKaROLjQAkAgAFAAgKaROLjQAkAgAAAA==.Trogdoor:BAAANQAECgIJAgAAAA==.Trokom:BAABNQAECoEoAAIFAAkKryYEAQD1AwAFAAkKryYEAQD1AwABNQAECgkKKAAFAK8mAA==.Trokopally:BAAANQAECgYIBgABNQAECgkKKAAFAK8mAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAABNQAECoElAAMWAAgK7g2gagDHAQAWAAgK7g2gagDHAQAXAAMKiwecSQCNAAAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ul='Ullrian:BAAANQAECggICAAAAA==.',
Un='Uncletrump:BAAANQADCgYIBgAAAA==.',
Ur='Urbanmech:BAABNQAECoEbAAILAAgKSh7pEACaAgALAAgKSh7pEACaAgAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECgkJJwAeANMSAA==.Vandermark:BAABNQAECoEnAAUeAAkK0xLeFABZAgAeAAkK0xLeFABZAgAMAAIKIBt6LACnAAAcAAIKxgUmiQBLAAAdAAIKlAXPKABJAAAAAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Viaos:BAAANQAECgUIDwAAAA==.Vidrus:BAAANQADCgcIDQAAAA==.Vilkas:BAAANQAFFAEIAQABNQAFFAQIBAAGAAAAAA==.Viserion:BAAANQADCgYIEgAAAA==.',
Wa='Waddledoo:BAABNQAECoEeAAIEAAgKkx8PHgC/AgAEAAgKkx8PHgC/AgAAAA==.Warmaku:BAAANQAECgYIEgAAAA==.',
Wh='Whïteoak:BAAANQAECgcIDgAAAA==.',
Wi='Wienz:BAAANQADCgMIAwAAAA==.Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAABNQAECoEdAAIJAAkKCiBADwAPAwAJAAkKCiBADwAPAwAAAA==.Xanyp:BAAANQAECgEJAwABNQAECgkJHQAJAAogAA==.',
Xe='Xeletath:BAAANQADCggIFgAAAA==.Xerg:BAAANQADCgUIBQABNQAECggIHAAZAEIZAA==.',
Xi='Xinaveruk:BAAANQAECgcIBwAAAA==.',
Xo='Xoro:BAAANQAECgQIBgAAAA==.',
Xr='Xrxyz:BAAANQADCgEIAQAAAA==.',
Xs='Xshamster:BAABNQAECoEgAAMEAAgKehsZLgBoAgAEAAgKehsZLgBoAgAVAAEKdxQn9QA5AAAAAA==.',
Ye='Yewna:BAAANQAECgIIAwABNQAECgkJJwAEAGwkAA==.',
Za='Zaarf:BAAANQADCgYIBgAAAA==.Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgcIDQAAAA==.Zachpri:BAAANQAECgEIAQAAAA==.Zanyr:BAAANQADCgMIAQABNQAECgkJHQAJAAogAA==.Zau:BAABNQAECoEcAAMYAAgKABwhBABfAgAYAAcKKx0hBABfAgAWAAQKPxPmuAD3AAAAAA==.',
Zo='Zodiac:BAAANQADCgUIBQABNQAECgkJHgAFAAUiAA==.Zolja:BAAANQAECgMIAwAAAA==.Zoney:BAAANQAECgIIAwAAAA==.Zordlon:BAAANQAECgQICQAAAA==.',
Zu='Zukem:BAABNQAECoEfAAIDAAgKgiJ0GwD3AgADAAgKgiJ0GwD3AgAAAA==.Zulelphie:BAAANQADCgMIBAAAAA==.Zuli:BAAANQAECgEIAQABNQAECgQIBAAGAAAAAA==.',
Zy='Zyariah:BAAANQADCgYICwAAAA==.Zyvea:BAAANQAECgcIEQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
