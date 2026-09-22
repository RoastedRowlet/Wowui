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

local lookup = {'Unknown-Unknown','Mage-Arcane','Priest-Holy','Shaman-Restoration','DeathKnight-Unholy','Evoker-Devastation','Evoker-Preservation','DemonHunter-Vengeance','Priest-Shadow','Paladin-Protection','Shaman-Elemental','Warlock-Affliction','Druid-Balance','Paladin-Retribution','Paladin-Holy','Warlock-Destruction','Warlock-Demonology','Druid-Guardian','Warrior-Protection','Monk-Mistweaver','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Feral','Priest-Discipline','DeathKnight-Frost','Evoker-Augmentation','DeathKnight-Blood','Mage-Frost','Druid-Restoration',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Adder:BAAANQADCgIIAgAAAA==.Adelgeise:BAAANQADCggJEgABNQAECggJEAABAAAAAA==.Adrua:BAAANQADCgUIBgAAAA==.Adym:BAAANQAECgcJEwAAAA==.',
Ag='Agave:BAAANQAECgYJDwAAAA==.',
Ai='Aiyah:BAAANQAECgQICAAAAA==.',
Al='Altarboi:BAAANQAECgEJAQAAAA==.Alüçard:BAAANQAECgQICgAAAA==.',
Am='Amoraniel:BAABNQAECoEZAAICAAgKMByVUgCUAgACAAgKMByVUgCUAgAAAA==.',
An='Anavar:BAAANQAECgYIBgAAAA==.Andrar:BAAANQADCgYIBwAAAA==.Andres:BAAANQAFFAEIAQAAAA==.Andresra:BAABNQAECoEdAAICAAgKbR5jOwDaAgACAAgKbR5jOwDaAgABNQAFFAEIAQABAAAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAAANQAECgQIDQAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.',
As='Asterin:BAAANQADCgUIBwAAAA==.',
Au='Augtism:BAAANQADCgMIAwABNQAECgcJDgABAAAAAA==.',
Av='Avâtre:BAAANQAECgQJBQAAAA==.',
Ba='Baguette:BAAANQAECgUIDAAAAA==.Bajingobomb:BAAANQAECgYJEAAAAA==.Bakblood:BAAANQABCgYICAAAAA==.Bakshung:BAAANQADCgYIBgAAAA==.Barkruffalo:BAAANQADCgEJAQAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.Barrybonds:BAAANQADCggIDAAAAA==.',
Be='Be:BAAANQAECgYIDAAAAA==.Beckyoncé:BAAANQAECgYJDwAAAA==.Bedris:BAAANQAECgQJCAAAAA==.Beerticus:BAAANQAECgYIDgAAAA==.',
Bi='Bigdingus:BAAANQAECgcJDgAAAA==.Binggles:BAACNQAFFIEWAAICAAcKRB5xAADfAgACAAcKRB5xAADfAgA1AAQKgR0AAgIACQqTJYIMAJEDAAIACQqTJYIMAJEDAAAA.',
Bl='Blacksheep:BAAANQAECgIIAgAAAA==.Blôôðhôôf:BAAANQADCgQIBAABNQAECgQJBQABAAAAAA==.',
Bo='Bokinar:BAAANQAECggJBgAAAA==.Bomboclaat:BAAANQAECgIIBgABNQAECgYIDwABAAAAAA==.Boolay:BAAANQAECgQJBwABNQABCgUIBQABAAAAAA==.Boomcommand:BAAANQADCgEIAgAAAA==.Boosteyboy:BAAANQADCgUIBQAAAA==.Bosmina:BAABNQAECoEeAAIDAAgKqxnkMAAyAgADAAgKqxnkMAAyAgAAAA==.',
Br='Braei:BAAANQAECgUJCwAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Brenmonk:BAAANQAECgUJCQAAAA==.Brenpriest:BAAANQADCgYIBgAAAA==.Brenshammy:BAAANQADCgUIBQAAAA==.',
Bu='Bubblebaddie:BAAANQAECgMIBQAAAA==.Bubblicous:BAAANQADCgYIBgAAAA==.Bugenhagen:BAABNQAECoEeAAIEAAgKtSQECwA2AwAEAAgKtSQECwA2AwAAAA==.Butchers:BAAANQADCgUIBgAAAA==.Buttpaladin:BAAANQAECgYIDAAAAA==.',
Ca='Cardib:BAACNQAFFIEHAAIFAAQKjBtaAwBqAQAFAAQKjBtaAwBqAQA1AAQKgRwAAgUACQo/JBcGAIADAAUACQo/JBcGAIADAAAA.Cavos:BAAANQAECgYJEwAAAA==.',
Ce='Centradin:BAAANQAECgIIBAAAAA==.Cernsarn:BAAANQAECgYIDAAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Chiri:BAEBNQAECoEZAAMGAAkKFhMdEAD9AQAGAAgKgBEdEAD9AQAHAAMKEgNKMgCAAAAAAA==.Chvngus:BAAANQAECgcJEQAAAA==.',
Ci='Citizencain:BAAANQAECgQIBwAAAA==.',
Cl='Claytnbigsby:BAAANQAECgMIBwAAAA==.',
Co='Cocheeze:BAAANQADCgQIBAAAAA==.Cogswell:BAAANQADCggIEgAAAA==.Condor:BAEANQAECggICwAAAA==.Coohwhip:BAAANQADCggJCwAAAA==.Cornorgan:BAAANQAECgUIBQAAAA==.Cowbut:BAAANQADCgEIAQAAAA==.',
Cr='Crakidos:BAAANQADCgQJBAAAAA==.Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAAANQAECgMJAwAAAA==.Cristobal:BAAANQAECgQIBAAAAA==.Crunkshot:BAAANQADCgMIBAAAAA==.',
Cy='Cydea:BAAANQAECgIJAwAAAA==.',
Da='Dagidan:BAABNQAECoEcAAIIAAgKGw9MCQC1AQAIAAgKGw9MCQC1AQAAAA==.',
De='Dead:BAAANQADCggICAAAAA==.Demontotems:BAAANQADCgYJBgAAAA==.Demotoxi:BAAANQAECgUJDwAAAA==.Deriso:BAAANQAECgcJDAAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCggIDAABAAAAAA==.Destrozinth:BAAANQAECgYICwAAAA==.Dethorok:BAAANQAECgYIEAAAAA==.Deuce:BAAANQABCgIJAQAAAA==.Deåth:BAAANQADCgYIDQABNQAECgEIAQABAAAAAA==.',
Di='Diagonpally:BAAANQADCgYIDgABNQAECggJHgAEALUkAA==.Dib:BAAANQADCgYIBgAAAA==.Digey:BAAANQAECgUJCAAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAAANQAECgUICAAAAA==.',
Do='Dontlookatme:BAAANQABCgUJBQAAAA==.Dopeaf:BAAANQADCgcIDAAAAA==.Dottër:BAAANQADCgUICwABNQAECgEIAQABAAAAAA==.',
Dr='Drakbek:BAAANQAECgEIAQAAAA==.Dreadshot:BAAANQADCgYIBgAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dronebot:BAABNQAECoElAAIJAAgK/xWSFABYAgAJAAgK/xWSFABYAgAAAA==.Drucifer:BAAANQADCggIDwAAAA==.',
Du='Durros:BAAANQAECgMJAwAAAA==.Dustyshotz:BAAANQADCgUIBQAAAA==.',
Eb='Eboger:BAAANQAECgIIAgAAAA==.',
El='Elunelphie:BAAANQADCgUIBQAAAA==.',
Em='Embody:BAAANQAECgQJCAAAAA==.Emiree:BAAANQAECgIIAgAAAA==.',
En='Endlyss:BAAANQAECgcJEgAAAA==.',
Er='Erasmas:BAAANQAECggJEAAAAA==.Erzascarlét:BAABNQAECoEeAAIKAAgKHBkTEAAYAgAKAAgKHBkTEAAYAgAAAA==.',
Es='Essentia:BAAANQABCgEIAQAAAA==.',
Eu='Euphoricx:BAAANQAECgYICwAAAA==.',
Ev='Evildeader:BAAANQADCggIGQABNQAECgQIBAABAAAAAA==.Eviltotems:BAAANQAECgQIBAAAAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAABNQAECoEYAAMLAAgKUhx8JgCEAgALAAgKUhx8JgCEAgAEAAEKMhEMyQBFAAAAAA==.Fantasma:BAAANQADCgYIDwAAAA==.',
Fe='Fear:BAAANQAECgIIAgAAAA==.',
Fi='Findal:BAAANQADCggICQABNQABCgIIAgABAAAAAA==.Fistymoo:BAEANQADCgMIAwABNQAECgkJGQAGABYTAA==.Fivemagics:BAAANQAECgcIEAAAAA==.',
Fl='Fleaboy:BAAANQAECgYJCwAAAA==.Flist:BAAANQAECgYIDwAAAA==.Floof:BAAANQADCgYICQAAAA==.',
Fo='Foe:BAAANQAECgQIBAAAAA==.Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAAANQAECgQJCAAAAA==.Freesia:BAAANQADCggIFQAAAA==.Fruitjuice:BAAANQADCggICAAAAA==.',
Fx='Fxce:BAAANQAECgUIDAAAAA==.',
['Fâ']='Fâmine:BAAANQADCggICAAAAA==.',
Ga='Gaothan:BAAANQAECgEJAQAAAA==.',
Gh='Ghulz:BAAANQAECgcIEgAAAA==.',
Gi='Gibsmedats:BAAANQAECgYJEAAAAA==.',
Gl='Glaiven:BAAANQAECgcJEwAAAA==.Glasscleaner:BAAANQAECgcICwABNQAFFAIIBAABAAAAAA==.Glenmorangie:BAAANQAECgYICwAAAA==.',
Gn='Gnartusk:BAAANQAECgUJCwAAAA==.',
Go='Goober:BAAANQADCgEIAQABNQADCggJCgABAAAAAA==.',
Gr='Greens:BAAANQAECgUJCQAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Gremory:BAAANQADCgYJCwABNQADCggIDAABAAAAAA==.Grillvy:BAAANQADCgIIBgAAAA==.Grumbo:BAAANQADCgYIBgABNQAECgIJAgABAAAAAA==.Grïma:BAABNQAECoEeAAIMAAgKZBpLAgCnAgAMAAgKZBpLAgCnAgAAAA==.',
Gs='Gsus:BAAANQADCggICAABNQAECgUIEAABAAAAAA==.',
Gu='Gueritestje:BAAANQAECgUJDgAAAA==.Guzzlord:BAAANQAECgcJEwAAAA==.',
Ha='Halfman:BAAANQAECgEIAQAAAA==.Hanekawa:BAAANQADCgUJBQABNQAECgcIDgABAAAAAA==.Harfnar:BAAANQABCggICAABNQADCgEIAQABAAAAAA==.',
Hb='Hboozing:BAAANQAECgYIEQAAAA==.',
He='Heayt:BAAANQABCgIIBAAAAA==.Heleous:BAAANQADCgMIAwABNQADCgYIBgABAAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Hipdrop:BAAANQAECgMIAwAAAA==.Hitoshura:BAAANQAECgQIBwAAAA==.',
Ho='Holyginger:BAAANQAECgIJAwAAAA==.Holyglizzy:BAAANQAECgYICwAAAA==.Holymajìk:BAAANQABCgIIAwAAAA==.',
Hy='Hypérîon:BAAANQAECgQIBQAAAA==.',
Ia='Iagging:BAAANQAECgcJEgABNQAFFAIIBAABAAAAAA==.',
Ik='Ikiryo:BAEANQAECgIIAwAAAA==.',
Im='Imtuggdup:BAAANQAECgcJEwAAAA==.Imzachedup:BAAANQADCgYICAAAAA==.',
In='Infidel:BAABNQAECoEdAAINAAgK9CR6CQBbAwANAAgK9CR6CQBbAwAAAA==.Invert:BAAANQADCgUJBQAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgEIAwAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQAAAA==.',
Ir='Irisharcher:BAAANQAECgEIAQAAAA==.Irishman:BAAANQADCggJGAAAAA==.',
It='Itazki:BAAANQAECgcJDwAAAA==.',
Ja='Jaft:BAAANQADCgUIBQAAAA==.Jalter:BAAANQAFFAIIBAAAAA==.',
Je='Jediknight:BAAANQAECgMIBAAAAA==.Jenga:BAAANQAECgcJDAAAAA==.Jergal:BAAANQAECgUICQAAAA==.Jertdor:BAAANQADCgQIBAAAAA==.',
Jf='Jf:BAABNQAECoEeAAMOAAgKHRW0bQC0AQAOAAcKihO0bQC0AQAPAAgK2QnCTwCzAQAAAA==.',
Ji='Jinkala:BAAANQABCgQIBAAAAA==.Jitzakkal:BAACNQAFFIEMAAMQAAUK/SWFAgDbAAARAAMKeiaLBgBWAQAQAAIKQSWFAgDbAAA1AAQKgR8AAxAACQoSJjEIAGECABEABwqtJV4WAOICABAABgpkJDEIAGECAAAA.',
Jn='Jn:BAAANQADCgcIDAAAAA==.',
Jo='Johnpaladin:BAABNQAECoEZAAIOAAgKMCXPDgBdAwAOAAgKMCXPDgBdAwAAAA==.Joshswims:BAAANQAECgQIBAAAAA==.',
Js='Js:BAAANQADCgYICgAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECggJHgACACMkAA==.Juleita:BAAANQABCgQIBAAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kapena:BAAANQAECggJBgAAAA==.Kardinal:BAABNQAECoEfAAQRAAkK+R9HCABSAwARAAkK+R9HCABSAwAQAAUK9xuEGQCGAQAMAAEKwRvRHABHAAAAAA==.Kargan:BAAANQADCgYIBgABNQAECgIJAgABAAAAAA==.',
Ke='Keladorn:BAAANQAECgUICQAAAA==.',
Kh='Khanyiso:BAAANQAECgUJDgAAAA==.Kharak:BAAANQAECgUJDQABNQABCgIIAgABAAAAAA==.',
Ki='Kichii:BAAANQAECgMIAwAAAA==.Kieran:BAAANQAECgYJDwAAAA==.Kilsaurys:BAABNQAECoEbAAMNAAgKSh0SGwCcAgANAAgKSh0SGwCcAgASAAUKugwvHADnAAAAAA==.Kirakishou:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.Kismete:BAAANQAECgYICQAAAA==.',
Ko='Konstantine:BAAANQAECgQJBwAAAA==.',
Kr='Krittykitkat:BAAANQAECgIIAgABNQAECgYIBgABAAAAAA==.Kryptocron:BAAANQABCgYICgAAAA==.',
Kw='Kwazlock:BAAANQADCgEIAQAAAA==.',
Ky='Kysoti:BAAANQADCgQIBAAAAA==.',
['Kí']='Kítsune:BAAANQADCggIHAAAAA==.',
La='Laprimera:BAAANQADCgcJFAAAAA==.Lasticon:BAAANQAECgcJBwAAAA==.Lazyjade:BAAANQAECgYJDwAAAA==.',
Le='Lenarius:BAAANQABCgUJBQABNQABCgYIBgABAAAAAA==.Leonidass:BAAANQADCgUIBQAAAA==.Leyline:BAAANQADCgYJCwAAAA==.',
Li='Lichborne:BAAANQADCgcIBwAAAA==.Lilgangster:BAAANQADCgIJAgAAAA==.',
Lo='Lockofdirish:BAAANQADCgUJBQAAAA==.Lorfirandor:BAAANQADCgUIBQAAAA==.Lorynn:BAAANQAECgYIDQAAAA==.',
Ma='Madwe:BAAANQAECgIIAgAAAA==.Magturri:BAAANQAECgYJEAAAAA==.Majìkstik:BAAANQABCgIIAgAAAA==.Mamameatmode:BAAANQAECgUIBwAAAA==.Marlbororeds:BAAANQAECgYICgAAAA==.Maxfirepower:BAAANQADCgYIEQAAAA==.Maxfrogpower:BAAANQADCgUJBQAAAA==.Maxsunward:BAAANQAECgEJAgAAAA==.',
Me='Meepasaurus:BAABNQAECoEdAAITAAgK5BzMBQCfAgATAAgK5BzMBQCfAgAAAA==.Megaforce:BAAANQAECgEIAQAAAA==.Mellky:BAABNQAECoEeAAIUAAgK9yBoBgDtAgAUAAgK9yBoBgDtAgAAAA==.Metanoia:BAAANQAECgcIEwABNQAECgkJHwARAPkfAA==.',
Mg='Mgamer:BAAANQADCgYJBgAAAA==.',
Mi='Mib:BAEANQAECggICgABNQAECggICwABAAAAAA==.Mibb:BAEBNQAECoEWAAICAAkKYBuZQgDDAgACAAkKYBuZQgDDAgABNQAECggICwABAAAAAA==.Midnitetrvlr:BAAANQAECgYIDwAAAA==.Migothedruid:BAAANQADCgEIAQAAAA==.Mirren:BAAANQAECgcJEwAAAA==.Missmoans:BAAANQADCgYICAABNQAECgYJDgABAAAAAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Momojojo:BAAANQAECgYJEgAAAA==.Monre:BAAANQAECgMIBQABNQAECgUIBQABAAAAAA==.Moonflame:BAABNQAECoEXAAIDAAgK0xtNKABgAgADAAgK0xtNKABgAgAAAA==.Mooriah:BAAANQAECgUJDgAAAA==.Mordekhuul:BAAANQAECgcJDQAAAA==.Motowa:BAAANQAECgIIAgAAAA==.',
Mp='Mpkshaman:BAAANQAECgcIBwAAAA==.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynche:BAAANQADCgYJBgABNQAECgQJBQABAAAAAA==.Mynchus:BAAANQAECgQJBQAAAA==.Mysterydh:BAAANQAECgEIAQAAAA==.Mysterypala:BAAANQAECgUJCgAAAA==.Mysteryvoke:BAAANQAECgQJCAAAAA==.',
Na='Naneko:BAAANQAECgQJBwAAAA==.',
Ne='Neelix:BAAANQAECgUJCAAAAA==.Nehi:BAAANQAECggJCQAAAA==.Neotahr:BAABNQAECoEbAAIVAAgKEgyOIQDRAQAVAAgKEgyOIQDRAQAAAA==.Neuron:BAEANQABCgUICgABNQAECgIIAwABAAAAAA==.',
Ni='Nickiminajj:BAAANQAECggICAAAAA==.Nismoto:BAABNQAECoEeAAIWAAgK1RAnQgAvAgAWAAgK1RAnQgAvAgAAAA==.Nitehunter:BAAANQAECgUJCgAAAA==.',
No='Noobert:BAAANQAECgEJAQAAAA==.Novademic:BAAANQAECgQJBgAAAA==.',
['Nö']='Növacaïn:BAAANQAECgEIAQAAAA==.',
Og='Ognikkay:BAABNQAECoEdAAIXAAgK8h0zBADXAgAXAAgK8h0zBADXAgAAAA==.',
Oy='Oyea:BAAANQABCgIIAgABNQAECgYJDwABAAAAAA==.',
Pa='Pabiloneta:BAAANQAECgEJAQABNQAFFAEIAQABAAAAAA==.Pallyana:BAAANQAECgcIEgAAAA==.Palosdin:BAAANQADCgYIBgAAAA==.Papapump:BAAANQADCgQJBAAAAA==.Parsleyposh:BAAANQADCgYICAABNQAECgIJAgABAAAAAA==.Pass:BAAANQADCgIIAgABNQAECgYIDwABAAAAAA==.',
Pe='Perridan:BAAANQADCggIFAAAAA==.',
Ph='Phalandrel:BAAANQAECggJBwAAAA==.',
Pi='Pinkponyclub:BAAANQAECgYIDwAAAA==.Pinkyshock:BAABNQAECoEkAAIKAAgK8RehDgAxAgAKAAgK8RehDgAxAgAAAA==.Pista:BAAANQADCgIIAQAAAA==.',
Po='Pog:BAAANQAECgIIAgABNQAECgQICAABAAAAAA==.Portholes:BAAANQADCgUICQAAAA==.',
Pr='Praystatiøn:BAAANQADCgYJCgAAAA==.',
Ps='Psyop:BAAANQAECgQJDQABNQAECgkJHQADAM8fAA==.',
Pu='Punked:BAAANQADCgYIBgAAAA==.Purplepain:BAAANQAECgUIBQABNQAFFAMJBAABAAAAAA==.Purplod:BAAANQAECgcJEwAAAA==.',
Py='Pyatpree:BAAANQADCgcIDgAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
Qi='Qing:BAAANQAECgUIEAAAAA==.',
Qy='Qybxboogies:BAAANQAECgYICQAAAA==.',
Ra='Raensong:BAAANQAECgIJAgAAAA==.Rainingarrow:BAAANQABCgIIAwAAAA==.Raisa:BAAANQAECggIEgAAAA==.Rakarum:BAAANQAECgEJAQAAAA==.Rasar:BAAANQAECgYJDwAAAA==.Rathew:BAAANQAECgYJEAAAAA==.Rawnext:BAAANQAECgYJDQAAAA==.',
Re='Revenger:BAAANQABCgMIAgAAAA==.Revoker:BAABNQAECoEeAAMVAAgKmgyPKACCAQAVAAcKuguPKACCAQAWAAUKPQzbngAiAQAAAA==.',
Ri='Riddlez:BAABNQAECoEeAAMDAAgKmSU9BgBkAwADAAgKmSU9BgBkAwAYAAUKsCKgBQDtAQAAAA==.Riott:BAAANQABCgQIAwAAAA==.',
Ro='Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECgUIBwAAAA==.Rox:BAAANQAECgQJBwAAAA==.Royle:BAAANQADCggICAAAAA==.Roywar:BAAANQADCgQJBAAAAA==.',
['Ré']='Réîgn:BAAANQAECgYJDAAAAA==.',
Sa='Sacrus:BAAANQAECgIJAgAAAA==.Samael:BAAANQADCgYIBgAAAA==.Sarah:BAABNQAECoEYAAMVAAkKcyLXCAAXAwAVAAkKcyLXCAAXAwAWAAEKcxDX6gBEAAAAAA==.',
Sc='Scalelord:BAAANQADCgYJCwABNQADCggIDAABAAAAAA==.Scoobear:BAAANQAECgMIBgABNQAECgYICwABAAAAAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senisia:BAAANQADCgQIBAAAAA==.Senjougahara:BAACNQAFFIEIAAIZAAUKEhAJAgCWAQAZAAUKEhAJAgCWAQA1AAQKgScAAhkACQqRI7wEAGsDABkACQqRI7wEAGsDAAAA.Seriyah:BAABNQAECoEYAAIXAAkKJxZ7BgBsAgAXAAkKJxZ7BgBsAgAAAA==.Serph:BAAANQAECgEJAQABNQAECgYJDgABAAAAAA==.',
Sh='Shabane:BAAANQAECgUJCwAAAA==.Shame:BAABNQAECoEbAAIJAAgKAxPqFgA2AgAJAAgKAxPqFgA2AgAAAA==.Shankey:BAAANQADCgYIBgAAAA==.Shasta:BAAANQADCgQIBAAAAA==.Shinobi:BAAANQAECgQJCAAAAA==.Shirls:BAAANQAECgcJEgAAAA==.Shivak:BAABNQAECoEcAAIaAAgKIhINBgDuAQAaAAgKIhINBgDuAQAAAA==.Shivanie:BAAANQAECgQIBQAAAA==.Shock:BAAANQAECgQICQAAAA==.Shredderella:BAAANQAECgcJEwAAAA==.Shrug:BAAANQAECgcJEwAAAA==.Shubie:BAAANQABCgIIAgABNQADCgUICwABAAAAAA==.',
Si='Sicwiddit:BAAANQAECgIJAgAAAA==.',
Sk='Skeeda:BAAANQAECgEIAQAAAA==.Skylinex:BAAANQAECgcICwAAAA==.Skylinez:BAAANQADCgYIDAAAAA==.Skïttles:BAAANQAECgYJDgAAAA==.',
Sl='Sleezball:BAAANQAECgUJDAAAAA==.',
So='Softie:BAAANQAECgEIAQABNQAECgcJEAABAAAAAA==.Sonictide:BAAANQAECgEIAwAAAA==.Soulscream:BAAANQAECggJDwAAAA==.',
Sp='Spaghetto:BAAANQAECgcJEQAAAA==.Sprite:BAAANQADCgQJBAAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgcIDwAAAA==.',
Su='Suzel:BAAANQADCggIDAAAAA==.',
Sy='Sydaria:BAAANQABCgEJAQAAAA==.Synder:BAAANQAECgYJDwAAAA==.',
Ta='Tainin:BAAANQAECgUJCwAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQAECgEIAQAAAA==.Tarynna:BAAANQAECgUJCwAAAA==.Tazerface:BAAANQAECgUICAAAAA==.',
Te='Tekin:BAAANQAECgYJEAAAAA==.Teleprompter:BAAANQAECgIJAgAAAA==.Telrissan:BAAANQAECgUJBwAAAA==.Tenyroldemon:BAAANQAECgQJDAAAAA==.',
Th='Thald:BAAANQAECgYIEAAAAA==.Thaznotmilk:BAAANQADCgIJAgAAAA==.',
Ti='Timzilla:BAAANQADCgcIBwABNQAECggJGwAbADwaAA==.Tinytip:BAAANQADCgYIBgAAAA==.Tisakna:BAABNQAECoEeAAMCAAgKIyQ9UACbAgACAAcKQCM9UACbAgAcAAMKjCKsEAAjAQAAAA==.',
To='Togon:BAAANQAECggIAQAAAA==.Tool:BAAANQADCggJCgAAAA==.Tostitos:BAAANQADCggICwAAAA==.',
Tr='Tralgina:BAAANQAECgEIAgABNQAECggIIQAKAFEaAA==.Trask:BAAANQAECgcJEwAAAA==.Trogdoor:BAAANQAECgIJAgAAAA==.Trokom:BAABNQAECoEkAAICAAkKryZuAAAEBAACAAkKryZuAAAEBAABNQAECgkKJAACAK8mAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAABNQAECoEeAAMRAAgK5A0tUwDVAQARAAgK5A0tUwDVAQAQAAMKiwdmQwCTAAAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ur='Urbanmech:BAAANQAECgcJEgAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECggJHgAdANQPAA==.Vandermark:BAABNQAECoEeAAUdAAgK1A8UIQCCAQAdAAcKtg4UIQCCAQASAAIKpxchJQCQAAANAAIKxgV6eABQAAAXAAIKlAUFIQBKAAAAAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Viaos:BAAANQAECgUIDwAAAA==.Vidrus:BAAANQADCgcIDQAAAA==.Vilkas:BAAANQAFFAEIAQABNQAFFAQIBAABAAAAAA==.Viserion:BAAANQADCgYIEgAAAA==.',
Wa='Waddledoo:BAAANQAECgcJEwAAAA==.Warmaku:BAAANQAECgYIDQAAAA==.',
Wh='Whïteoak:BAAANQAECgcJBwAAAA==.',
Wi='Wienz:BAAANQADCgMJAwAAAA==.Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAABNQAECoEdAAIbAAkKCiAeCwAnAwAbAAkKCiAeCwAnAwAAAA==.Xanyp:BAAANQAECgEJAwABNQAECgkJHQAbAAogAA==.',
Xe='Xeletath:BAAANQADCgYIDgAAAA==.Xerg:BAAANQADCgUIBQABNQAECgUIEAABAAAAAA==.',
Xi='Xinaveruk:BAAANQAECgcJBwAAAA==.',
Xo='Xoro:BAAANQAECgEIAgAAAA==.',
Xr='Xrxyz:BAAANQADCgEIAQAAAA==.',
Xs='Xshamster:BAABNQAECoEYAAMEAAgK4Bq+IgCEAgAEAAgK4Bq+IgCEAgALAAEKdxSH1AA7AAAAAA==.',
Ye='Yewna:BAAANQAECgIIAwABNQAECggJHgAEALUkAA==.',
Za='Zaarf:BAAANQADCgYIBgAAAA==.Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgcIDQAAAA==.Zachpri:BAAANQAECgEIAQAAAA==.Zanyr:BAAANQADCgMIAQABNQAECgkJHQAbAAogAA==.Zau:BAAANQAECgcJEwAAAA==.',
Zo='Zolja:BAAANQADCggJGQAAAA==.Zoney:BAAANQAECgIIAwAAAA==.Zordlon:BAAANQAECgQICQAAAA==.',
Zu='Zukem:BAABNQAECoEdAAIWAAgKgiJREQAYAwAWAAgKgiJREQAYAwAAAA==.Zulelphie:BAAANQADCgMIBAAAAA==.',
Zy='Zyariah:BAAANQADCgUIBQAAAA==.Zyvea:BAAANQAECgQICgAAAA==.',
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
