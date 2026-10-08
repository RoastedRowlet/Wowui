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

local lookup = {'Hunter-Marksmanship','Paladin-Holy','Hunter-BeastMastery','Shaman-Restoration','Mage-Arcane','Unknown-Unknown','Paladin-Protection','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','DemonHunter-Devourer','Paladin-Retribution','Monk-Windwalker','Druid-Guardian','Mage-Frost','DeathKnight-Frost','Evoker-Devastation','Evoker-Preservation','Druid-Balance','DemonHunter-Vengeance','Priest-Shadow','DemonHunter-Havoc','Warrior-Protection','Warrior-Arms','Warlock-Demonology','Warlock-Destruction','Priest-Discipline','Warlock-Affliction','Monk-Brewmaster','Evoker-Augmentation','Monk-Mistweaver','Druid-Feral','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acidsword:BAAANQAFFAEIAQABNQAECgkJMQABABMeAA==.',
Ad='Adaria:BAAANQADCgMIAwAAAA==.Adder:BAAANQADCgIIAgAAAA==.Adelgeise:BAAANQAECgQIBAABNQAECgkJLQACALAjAA==.Adrua:BAAANQAECgQIBgAAAA==.Adym:BAABNQAECoEeAAIDAAgKNxEHZwAbAgADAAgKNxEHZwAbAgAAAA==.',
Ag='Agave:BAABNQAECoEiAAIEAAgKiw86ZACxAQAEAAgKiw86ZACxAQAAAA==.',
Ai='Aiyah:BAAANQAECgQICQAAAA==.',
Al='Altarboi:BAAANQAECgQICQAAAA==.Alüçard:BAAANQAECgQIEQAAAA==.',
Am='Amoraniel:BAABNQAECoEkAAIFAAgKIh7WZwCaAgAFAAgKIh7WZwCaAgAAAA==.',
An='Anavar:BAAANQAECgYIBwAAAA==.Andrar:BAAANQADCgYIBwAAAA==.Andres:BAAANQAFFAEIAQAAAA==.Andresra:BAABNQAECoEnAAIFAAgK0CC1UgDLAgAFAAgK0CC1UgDLAgABNQAFFAEIAQAGAAAAAA==.Anie:BAAANQADCgQIBAAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAAANQAECgQIDQAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.Arthusxoxo:BAAANQAECggIBgAAAA==.',
As='Asrael:BAAANQADCgYIBgABNQAECggIIAAHABQZAA==.Asterin:BAAANQADCgUICwAAAA==.',
At='Athená:BAAANQAECgEIAgAAAA==.',
Au='Augtism:BAAANQADCgMIAwABNQAECgcIEQAGAAAAAA==.',
Av='Avâtre:BAABNQAECoEUAAIIAAYKURqYYgDJAQAIAAYKURqYYgDJAQAAAA==.',
Ba='Baguette:BAAANQAECgUIDgAAAA==.Bajingobomb:BAABNQAECoEiAAMJAAgKZiHCGADeAgAJAAgK8yDCGADeAgAKAAYKtx2+QQDXAQAAAA==.Bakblood:BAAANQABCgYICAAAAA==.Bakshung:BAAANQADCgYIBgAAAA==.Barkruffalo:BAAANQADCgEIAQAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.Barnpall:BAAANQAECgYIBgAAAA==.Barrybonds:BAAANQADCggIDAAAAA==.Bayao:BAAANQAECgUIBgAAAA==.',
Be='Be:BAABNQAECoEZAAILAAcKVxk4UQAFAgALAAcKVxk4UQAFAgAAAA==.Beckyoncé:BAABNQAECoEhAAIMAAgKMSFrDgDyAgAMAAgKMSFrDgDyAgAAAA==.Bedris:BAABNQAECoEXAAQNAAYKkhEs2gAtAQANAAYK6wks2gAtAQAHAAMKJRiARQCwAAACAAEKXQKtGwEfAAAAAA==.Beerticus:BAABNQAECoEbAAIOAAcK+RsXGgBEAgAOAAcK+RsXGgBEAgAAAA==.',
Bi='Biar:BAAANQADCgEIAQAAAA==.Bigdingus:BAABNQAECoEXAAIPAAgKzRvzCwBsAgAPAAgKzRvzCwBsAgAAAA==.Binggles:BAACNQAFFIEkAAMFAAcKmyMzAQDbAgAFAAcKFyIzAQDbAgAQAAIKuiS6AgDZAAA1AAQKgSEAAgUACQquJYgYAGsDAAUACQquJYgYAGsDAAAA.',
Bl='Blacksheep:BAAANQAECgIIBAAAAA==.Blazze:BAAANQAECgQIBAABNQAECggIEgAGAAAAAA==.Blôôðhôôf:BAAANQADCgQIBAABNQAECggIEwAGAAAAAA==.',
Bo='Bokinar:BAAANQAECggICAAAAA==.Bomboclaat:BAAANQAECgIIBgABNQAECgkJHQAOAGcjAA==.Boolay:BAAANQAECgYIEwABNQABCgUIBQAGAAAAAA==.Boomcommand:BAAANQAECgEIAwAAAA==.Boosteyboy:BAAANQAECgYICwAAAA==.Boozing:BAAANQADCgMIAwABNQAECggIHAADAAIiAA==.Bosmina:BAABNQAECoEwAAILAAkK/Bo+KwCdAgALAAkK/Bo+KwCdAgAAAA==.',
Br='Braei:BAABNQAECoEZAAICAAcKMRNNZADFAQACAAcKMRNNZADFAQAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Brenhunt:BAAANQADCgYIDAAAAA==.Brenmonk:BAABNQAECoEYAAIOAAcKDwv8MQBQAQAOAAcKDwv8MQBQAQAAAA==.Brenpriest:BAAANQADCgYIBgAAAA==.Brenshammy:BAAANQADCgUIBQAAAA==.Bruenor:BAAANQADCgYIBgAAAA==.',
Bu='Bubblebaddie:BAAANQAECgMIBwAAAA==.Bubblicous:BAAANQADCgYIBgAAAA==.Bugenhagen:BAABNQAECoEwAAIEAAkKqyQDBQCQAwAEAAkKqyQDBQCQAwAAAA==.Butchers:BAAANQAECgEIAQAAAA==.Buttpaladin:BAABNQAECoEnAAINAAgKFhgOdgASAgANAAgKFhgOdgASAgAAAA==.',
Ca='Caliden:BAAANQAECgEIAQAAAA==.Cardib:BAACNQAFFIEQAAMJAAcKXhyxBQCoAQAJAAUKEyGxBQCoAQARAAMKwhApCgD1AAA1AAQKgSAAAwkACQpxJXISAA4DAAkACQpxJXISAA4DABEAAQrAHESIAE4AAAAA.Cavos:BAABNQAECoEdAAIMAAcKlxtdIQAiAgAMAAcKlxtdIQAiAgAAAA==.',
Ce='Centradin:BAAANQAECgIIBAAAAA==.Cernsarn:BAABNQAECoEfAAIKAAgKPxV7OQD/AQAKAAgKPxV7OQD/AQAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Chiri:BAEBNQAECoEfAAMSAAkKNBA7EwD7AQASAAkKNBA7EwD7AQATAAMKEgMkPwB/AAAAAA==.Chvngus:BAABNQAECoEkAAINAAgKQiJ/LQD0AgANAAgKQiJ/LQD0AgAAAA==.',
Ci='Citizencain:BAAANQAECgQIEwAAAA==.',
Cl='Claytnbigsby:BAAANQAECgMICQAAAA==.',
Co='Cocheeze:BAAANQADCgYICgAAAA==.Cogswell:BAAANQADCggIEgAAAA==.Condor:BAEANQAECggIDAAAAA==.Conmammoth:BAAANQAECgQIBAAAAA==.Coohwhip:BAAANQAECgEIAgAAAA==.Cornorgan:BAAANQAECgcIDgAAAA==.Corèl:BAAANQADCgIIAwAAAA==.Cowbut:BAAANQADCgEIAQAAAA==.',
Cr='Crakidos:BAAANQADCgQJBAAAAA==.Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAABNQAECoEWAAIUAAgKlxJLOwDvAQAUAAgKlxJLOwDvAQAAAA==.Cristobal:BAAANQAECgUIBgAAAA==.Crunkshot:BAAANQADCgMIBAAAAA==.',
Cu='Curnsarn:BAAANQAECgQIBAABNQAECggIHwAKAD8VAA==.',
Cy='Cydea:BAAANQAECgMIBQAAAA==.',
Da='Dagidan:BAABNQAECoEtAAIVAAkKwxIhCgANAgAVAAkKwxIhCgANAgAAAA==.Darktide:BAAANQAECggICAAAAA==.Dashel:BAAANQAECgQIBgABNQAECggIIgAWAJ4RAA==.Dayveni:BAAANQAECgEIAQAAAA==.',
De='Dead:BAAANQAECgEIAgAAAA==.Deathtoxi:BAAANQAECgIIAgAAAA==.Degey:BAAANQAECgEIAQAAAA==.Demontotems:BAAANQAECgEIBAAAAA==.Demotoxi:BAABNQAECoEdAAQMAAcKMhvHHgA8AgAMAAcKlRrHHgA8AgAXAAQKZhcEVgD5AAAVAAIKzQqsJgBRAAAAAA==.Deriso:BAAANQAECggIEQAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCggIDAAGAAAAAA==.Destrozinth:BAAANQAECgcICwAAAA==.Dethorok:BAABNQAECoEmAAIDAAkK8yMOBQCwAwADAAkK8yMOBQCwAwAAAA==.Deuce:BAAANQABCgIJAQAAAA==.Deåth:BAAANQAECgEIAwAAAA==.',
Di='Diagonpally:BAAANQADCgYIDgABNQAECgkJMAAEAKskAA==.Dib:BAAANQAECgQIBAAAAA==.Digey:BAABNQAECoEZAAMYAAgKqiEwBQAHAwAYAAgKqiEwBQAHAwAZAAEKMQzJMAE4AAAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAAANQAECgYIEgAAAA==.',
Do='Dontlookatme:BAAANQAECgEIBAAAAA==.Dopeaf:BAAANQADCgcIDAAAAA==.Dottër:BAAANQADCggIEwABNQAECgEIAwAGAAAAAA==.',
Dr='Drakbek:BAAANQAECgYICwAAAA==.Dreadshot:BAAANQADCgYIBgAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dronebot:BAABNQAECoFFAAIWAAgKjh6OEwCtAgAWAAgKjh6OEwCtAgAAAA==.Drucifer:BAAANQADCggIDwAAAA==.',
Du='Dud:BAAANQAECgYIBwABNQAECggIFAAEACgdAA==.Durros:BAAANQAECgcIEwAAAA==.Dustyshotz:BAAANQAECgEIAQAAAA==.',
Eb='Eboger:BAAANQAECgIIAwAAAA==.',
El='Elunelphie:BAAANQADCgUIBgAAAA==.',
Em='Embody:BAABNQAECoEXAAIUAAYKowxEXAA3AQAUAAYKowxEXAA3AQAAAA==.Emiree:BAAANQAECgIIAgAAAA==.',
En='Endlyss:BAABNQAECoEZAAINAAgK2xcpbQApAgANAAgK2xcpbQApAgAAAA==.',
Er='Erasmas:BAABNQAECoEtAAMCAAkKsCOhBACiAwACAAkKsCOhBACiAwANAAcK+BozdwAPAgAAAA==.Erzascarlét:BAABNQAECoEwAAIHAAkKGx7OCQDhAgAHAAkKGx7OCQDhAgAAAA==.',
Es='Essentia:BAAANQABCgEIAQAAAA==.',
Eu='Euphoricx:BAAANQAECgYIDgAAAA==.',
Ev='Evildeader:BAAANQAECgYICAAAAA==.Eviltotems:BAAANQAECgUICgABNQAECgYICAAGAAAAAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAABNQAECoEqAAMIAAkKQh+0FgArAwAIAAkKQh+0FgArAwAEAAIKQAty5wBrAAAAAA==.Fantasma:BAAANQAECgEIAQAAAA==.',
Fe='Fear:BAAANQAECgIIAgAAAA==.',
Fi='Findal:BAAANQADCggICQABNQABCgMIAwAGAAAAAA==.Fistymoo:BAEANQADCgMIAwABNQAECgkJHwASADQQAA==.Fivemagics:BAABNQAECoEdAAMaAAgKARUdhwCmAQAaAAYKLhUdhwCmAQAbAAIKexS3UQB+AAAAAA==.',
Fl='Fleaboy:BAAANQAECgcIEgAAAA==.Flist:BAABNQAECoEdAAIOAAkKZyN+BAB/AwAOAAkKZyN+BAB/AwAAAA==.Floof:BAAANQADCgYIDwAAAA==.',
Fo='Foe:BAAANQAECgUIDwAAAA==.Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAABNQAECoEXAAIWAAYKAReeKwChAQAWAAYKAReeKwChAQAAAA==.Freesia:BAAANQAECgIIBQAAAA==.Fruitjuice:BAAANQAECgUICQAAAA==.',
Fx='Fxce:BAAANQAECgUIEgAAAA==.',
['Fâ']='Fâmine:BAAANQADCggICAAAAA==.',
Ga='Gaothan:BAAANQAECgEJAgAAAA==.',
Ge='Genjy:BAAANQABCgIIAgAAAA==.',
Gh='Ghulz:BAAANQAECgcIEgAAAA==.',
Gi='Gibsmedats:BAABNQAECoEhAAIXAAgKFw8pNADYAQAXAAgKFw8pNADYAQAAAA==.',
Gl='Glaiven:BAABNQAECoEcAAIMAAgKGBJDJQD9AQAMAAgKGBJDJQD9AQAAAA==.Glasscleaner:BAABNQAECoEVAAICAAkKfiIBCgBrAwACAAkKfiIBCgBrAwABNQAFFAUIDgATALEdAA==.Glenmorangie:BAABNQAECoEWAAMcAAkKMhqaBQAuAgAcAAcKihqaBQAuAgAWAAQKKxcPPAAgAQAAAA==.',
Gn='Gnartusk:BAABNQAECoEdAAIKAAcKhCHQHQCqAgAKAAcKhCHQHQCqAgAAAA==.',
Go='Goober:BAAANQADCgEIAQABNQAECgMIBQAGAAAAAA==.Gordrack:BAAANQAECgEIAQAAAA==.',
Gr='Greens:BAABNQAECoEfAAIUAAgKchtmIwCWAgAUAAgKchtmIwCWAgAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Gremory:BAAANQADCgYJCwABNQADCggIDAAGAAAAAA==.Grillvy:BAAANQADCgIIBgAAAA==.Grumbo:BAAANQAECgEIAgABNQAECgQICAAGAAAAAA==.Grïma:BAABNQAECoEpAAIdAAgKmB1RAwCqAgAdAAgKmB1RAwCqAgAAAA==.',
Gs='Gsus:BAAANQADCggICAABNQAECggIJAAeAH4aAA==.',
Gu='Gueritestje:BAABNQAECoEeAAIHAAgKUiC9CQDiAgAHAAgKUiC9CQDiAgAAAA==.Guzzlord:BAABNQAECoEcAAQTAAgKPAu9JwBUAQATAAcKkQm9JwBUAQASAAQKQQYKKgC2AAAfAAQKegjyFQCqAAAAAA==.',
Ha='Halfman:BAAANQAECgEIAgAAAA==.Handsomejack:BAAANQAECgIIBAABNQAECggIIgAJAGYhAA==.Hanekawa:BAAANQAECgEIAQABNQAFFAEIAQAGAAAAAA==.Harfnar:BAAANQABCggICAABNQADCgEIAQAGAAAAAA==.',
Hb='Hboozing:BAABNQAECoEcAAMDAAgKAiIQHwD/AgADAAgKAiIQHwD/AgABAAEKkxIGcwA/AAAAAA==.',
He='Healyhavok:BAAANQADCgIIAgAAAA==.Heayt:BAAANQABCgIIBAAAAA==.Heleous:BAAANQADCgMIAwABNQADCgYIBgAGAAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Hipdrop:BAAANQAECgMIBAAAAA==.Hitoshura:BAABNQAECoEWAAMJAAcKvSWdFgDuAgAJAAcKQSWdFgDuAgARAAUKCSU5MgDdAQAAAA==.Hittnrunn:BAAANQAECgEIAQAAAA==.',
Ho='Holyginger:BAAANQAECgUIDgAAAA==.Holyglizzy:BAABNQAECoEYAAINAAgKQhWdeQAJAgANAAgKQhWdeQAJAgAAAA==.Holymajìk:BAAANQAECgEIAQAAAA==.',
Hy='Hypérîon:BAAANQAECgQIBwAAAA==.',
Ia='Iagging:BAABNQAECoEVAAIgAAgK0iFPCQDbAgAgAAgK0iFPCQDbAgABNQAFFAUIDgATALEdAA==.',
Ik='Ikiryo:BAEANQAECgIICwAAAA==.',
Im='Imtuggdup:BAABNQAECoEbAAMFAAkKWB0fQwDvAgAFAAkKWB0fQwDvAgAQAAEKPhi9PQA4AAAAAA==.Imzachedup:BAAANQADCgYICAAAAA==.',
In='Infidel:BAABNQAECoErAAIUAAkKvyTHBACrAwAUAAkKvyTHBACrAwAAAA==.Invert:BAAANQAECgEIAQAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgEIBAAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQAAAA==.',
Ir='Irayne:BAAANQADCgQIBAAAAA==.Irisharcher:BAAANQAECgEIAQAAAA==.Irishbeauty:BAAANQADCgYIBgAAAA==.Irishfury:BAAANQADCgIIAgAAAA==.Irishman:BAAANQAECgQIBAAAAA==.',
Is='Isengardd:BAAANQAECgEIAQAAAA==.',
It='Itazki:BAABNQAECoEcAAMhAAgKKCBdBQD/AgAhAAgKKCBdBQD/AgAUAAEKHQyTogAwAAAAAA==.',
Ja='Jackpot:BAAANQADCgEIAQAAAA==.Jaft:BAAANQADCgYIEAAAAA==.Jalter:BAACNQAFFIEOAAITAAUKsR24BQDhAQATAAUKsR24BQDhAQA1AAQKgR0AAhMACQqTIukDAG0DABMACQqTIukDAG0DAAAA.',
Je='Jediknight:BAAANQAECgMIBQAAAA==.Jelial:BAAANQAECgEIAQAAAA==.Jenga:BAAANQAECgcIDwAAAA==.Jergal:BAABNQAECoEVAAIZAAgKwAopmgCxAQAZAAgKwAopmgCxAQAAAA==.Jertdor:BAAANQADCgQIBAAAAA==.',
Jf='Jf:BAABNQAECoEpAAMNAAgKTRm2YgBFAgANAAgKTRm2YgBFAgACAAgK2Qn3bwCgAQAAAA==.',
Ji='Jibbage:BAAANQAECgQIBAABNQAECgkJKwAUAL8kAA==.Jinkala:BAAANQABCgYIBwAAAA==.Jitzakkal:BAACNQAFFIEZAAMaAAcKxSUHAwAvAgAaAAUKXSUHAwAvAgAbAAIKyyaVAgDpAAA1AAQKgSEAAxsACQoSJugJAFACABoABwqtJeQsALkCABsABgpkJOgJAFACAAAA.',
Jn='Jn:BAAANQADCgcIDAAAAA==.',
Jo='Johnpaladin:BAABNQAECoElAAINAAkKWiW3BQDEAwANAAkKWiW3BQDEAwAAAA==.Joshswims:BAAANQAECgYIDwAAAA==.',
Js='Js:BAAANQADCgYICwAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECgkJMAAFAEIkAA==.Juleita:BAAANQABCgQIBAAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kapena:BAAANQAECggIDgAAAA==.Kardinal:BAABNQAECoErAAQaAAkKBiQEBQCfAwAaAAkKBiQEBQCfAwAbAAUK9xvbHQB3AQAdAAEKwRu6JQBEAAAAAA==.Kargan:BAAANQADCgcICAABNQAECgUICQAGAAAAAA==.Karliee:BAAANQAECgEIAQABNQAECgIIBQAGAAAAAA==.Karpathous:BAAANQAECggIBwAAAA==.',
Ke='Keladorn:BAABNQAECoEZAAINAAcKdSLWPwCwAgANAAcKdSLWPwCwAgAAAA==.',
Kh='Khanyiso:BAABNQAECoEgAAIHAAgKFBnREwBDAgAHAAgKFBnREwBDAgAAAA==.Kharak:BAABNQAECoEdAAIFAAcK4B/idwB4AgAFAAcK4B/idwB4AgABNQABCgMIAwAGAAAAAA==.',
Ki='Kichi:BAAANQADCgQIBAAAAA==.Kichii:BAAANQAECgQIDAAAAA==.Kieran:BAABNQAECoEiAAMWAAgKnhEPNQBTAQAWAAYKXQ4PNQBTAQALAAMKJAc/wAChAAAAAA==.Kilsaurys:BAABNQAECoEmAAQUAAkKahyaHgC5AgAUAAkKahyaHgC5AgAiAAcKrxLgJQDEAQAPAAUKugw+LwDYAAAAAA==.Kirakishou:BAAANQAECgIIAwABNQAFFAEIAQAGAAAAAA==.Kismete:BAAANQAECgcIEwAAAA==.',
Ko='Konstantine:BAAANQAECgcIEgAAAA==.',
Kr='Kravnoc:BAAANQADCgYIBgAAAA==.Krittykitkat:BAAANQAECgIIAgABNQAECgYIBwAGAAAAAA==.Kryptocron:BAAANQAECgMIAwAAAA==.',
Kw='Kwazlock:BAAANQADCgEIAQAAAA==.',
Ky='Kysoti:BAAANQADCgQIBAAAAA==.',
['Kí']='Kítsune:BAAANQADCggILQAAAA==.',
La='Laprimera:BAAANQAECgEIAQAAAA==.Lasticon:BAABNQAECoEUAAIDAAYKcwbM2QAbAQADAAYKcwbM2QAbAQABNQAECggICAAGAAAAAA==.Lazyjade:BAABNQAECoEiAAIWAAkKKxhrFgCFAgAWAAkKKxhrFgCFAgAAAA==.',
Le='Lenarius:BAAANQABCgUJBQABNQABCgYIBgAGAAAAAA==.Leonidass:BAAANQADCgUIBQAAAA==.Leyline:BAAANQADCgYICwAAAA==.',
Li='Lichborne:BAAANQADCgcIBwAAAA==.Lilgangster:BAAANQADCgIIAgAAAA==.',
Lo='Lockofdirish:BAAANQAECgEIAQAAAA==.Lorfirandor:BAAANQADCgYICwAAAA==.Lorynn:BAABNQAECoEdAAIFAAkK1BZhZwCbAgAFAAkK1BZhZwCbAgAAAA==.',
Ma='Madwe:BAAANQAECgcIEwAAAA==.Magturri:BAABNQAECoEiAAMDAAgKsxv4NACqAgADAAgKsxv4NACqAgABAAIKQAcBbABZAAAAAA==.Magvara:BAAANQAECgEIBAAAAA==.Majìkstik:BAAANQAECgEIAQAAAA==.Mamameatmode:BAAANQAECgUICAAAAA==.Marlbororeds:BAAANQAECgYICgAAAA==.Maxfirepower:BAAANQADCggIGQAAAA==.Maxfrogpower:BAAANQADCgcIDAAAAA==.Maxsunward:BAAANQAECgQICwAAAA==.',
Me='Meepasaurus:BAABNQAECoEnAAIYAAgKOyHuBQDrAgAYAAgKOyHuBQDrAgAAAA==.Megaforce:BAAANQAECgEIAwAAAA==.Mellky:BAABNQAECoEpAAIgAAgKbCWkBABHAwAgAAgKbCWkBABHAwAAAA==.Metanoia:BAABNQAECoEaAAIjAAgKnB/6EgDDAgAjAAgKnB/6EgDDAgABNQAECgkJKwAaAAYkAA==.',
Mg='Mgamer:BAAANQADCgYIBgAAAA==.',
Mi='Mib:BAEBNQAECoEVAAIJAAkKbBj2QQDuAQAJAAkKbBj2QQDuAQABNQAECggIDAAGAAAAAA==.Mibb:BAEBNQAECoEnAAIFAAkKgiCdLwAiAwAFAAkKgiCdLwAiAwABNQAECggIDAAGAAAAAA==.Midnitetrvlr:BAABNQAECoEYAAIJAAgKiAu7WQCCAQAJAAgKiAu7WQCCAQAAAA==.Migothedruid:BAAANQADCgEIAQAAAA==.Mirren:BAABNQAECoEeAAIQAAgK1xZCCQAQAgAQAAgK1xZCCQAQAgAAAA==.Missmoans:BAAANQADCgYICAABNQAECgcIGAAiAEMUAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Molyporph:BAAANQAECgEIAQAAAA==.Momojojo:BAABNQAECoEcAAIbAAcKHyDpBgCQAgAbAAcKHyDpBgCQAgAAAA==.Monre:BAAANQAECgMIBgABNQAECgcIDgAGAAAAAA==.Moonflame:BAABNQAECoEiAAILAAkKRRvxJgCxAgALAAkKRRvxJgCxAgAAAA==.Mooriah:BAABNQAECoEdAAIUAAcKPgRKaQD7AAAUAAcKPgRKaQD7AAAAAA==.Mordekhuul:BAABNQAECoEiAAIaAAkKdxzaHAD8AgAaAAkKdxzaHAD8AgAAAA==.Motowa:BAAANQAECgIIBgAAAA==.Mournhide:BAAANQAECggIBAAAAA==.',
Mp='Mpkshaman:BAAANQAECgcIEwAAAA==.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynche:BAAANQADCgYJBgABNQAECgYIDgAGAAAAAA==.Mynchus:BAAANQAECgYIDgAAAA==.Myrtne:BAAANQAECgEIAQAAAA==.Mysterydh:BAAANQAECgYIDgAAAA==.Mysterypala:BAAANQAECgUJDQAAAA==.Mysteryvoke:BAABNQAECoEXAAITAAcKSiQgCwDjAgATAAcKSiQgCwDjAgAAAA==.',
['Mä']='Mälförmïtÿ:BAAANQAECgEIAQABNQAECgcIFwAaAIMaAA==.',
Na='Naneko:BAAANQAECgYIEgAAAA==.',
Ne='Neelix:BAABNQAECoEXAAMDAAgKHgkzfgDiAQADAAgKHgkzfgDiAQABAAUKwAHiWgCTAAAAAA==.Nehi:BAAANQAECggICgAAAA==.Neotahr:BAABNQAECoEtAAIBAAkKwxC2IQAgAgABAAkKwxC2IQAgAgAAAA==.Neuron:BAEANQABCgUICgABNQAECgIICwAGAAAAAA==.',
Ni='Nickiminajj:BAAANQAECggICAAAAA==.Nismoto:BAABNQAECoEoAAIDAAgKJBGQaAAXAgADAAgKJBGQaAAXAgAAAA==.Nitehunter:BAABNQAECoEUAAIDAAcK6wkCmQCjAQADAAcK6wkCmQCjAQAAAA==.',
No='Noobert:BAAANQAECgUICgAAAA==.Novademic:BAAANQAECgUIEQAAAA==.',
['Nö']='Növacaïn:BAAANQAECgEIAgAAAA==.',
Of='Offseason:BAAANQADCgYIBgAAAA==.',
Og='Ognikkay:BAABNQAECoEpAAIhAAkK2x5uBAAkAwAhAAkK2x5uBAAkAwAAAA==.',
Or='Oranthør:BAAANQADCgUIBQAAAA==.',
Oy='Oyakev:BAAANQADCgUIBgAAAA==.Oyea:BAAANQAECgEIAQABNQAECgkJIgAWACsYAA==.',
Pa='Pabiloneta:BAAANQAECgQIBAABNQAFFAEIAQAGAAAAAA==.Pakami:BAAANQAECgYIBgAAAA==.Pallyana:BAABNQAECoEeAAINAAkKRhrNSQCRAgANAAkKRhrNSQCRAgAAAA==.Palosdin:BAAANQAECgIIAwAAAA==.Papapump:BAAANQADCgQJBAAAAA==.Parsleyposh:BAAANQADCgcICgABNQAECgQICAAGAAAAAA==.Pass:BAAANQAECgUIBQABNQAECgkJHQAOAGcjAA==.',
Pe='Perridan:BAAANQADCggIFAAAAA==.',
Ph='Phalandrel:BAABNQAECoEVAAIDAAkKiRWoWgA7AgADAAkKiRWoWgA7AgAAAA==.',
Pi='Pinkponyclub:BAABNQAECoEiAAICAAgK1ByOKACuAgACAAgK1ByOKACuAgAAAA==.Pinkyshock:BAABNQAECoFEAAIHAAgKdR1eEABxAgAHAAgKdR1eEABxAgAAAA==.Pista:BAAANQADCgIIAQAAAA==.',
Po='Pog:BAAANQAECgIIAgABNQAECgQICQAGAAAAAA==.Portholes:BAAANQAECgUIDAAAAA==.',
Pr='Praystatiøn:BAAANQADCgYICgAAAA==.',
Ps='Psyop:BAAANQAECgQIEAAAAA==.',
Pu='Punked:BAAANQADCgYIBgAAAA==.Purplepain:BAAANQAECgYIEAABNQAFFAUIDwAOAAUfAA==.Purplod:BAABNQAECoEeAAMRAAgKOwuhPwCHAQARAAgKggqhPwCHAQAKAAUKCQiHggDMAAAAAA==.',
Py='Pyatpree:BAAANQADCgcIDgAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
Qi='Qing:BAABNQAECoEkAAIeAAgKfhoECgBbAgAeAAgKfhoECgBbAgAAAA==.',
Qy='Qybxboogied:BAAANQAECgIIAgAAAA==.Qybxboogies:BAAANQAECggIDwAAAA==.Qybxboogyy:BAAANQADCggICgAAAA==.',
Ra='Raensong:BAAANQAECgUICAAAAA==.Rafterman:BAAANQAECgQIBAAAAA==.Rainingarrow:BAAANQAECgEIAQAAAA==.Raisa:BAABNQAECoElAAMaAAkKLR6PMACrAgAaAAgKzh2PMACrAgAbAAMKYBlyLwAAAQAAAA==.Rakarum:BAAANQAECgEIAgAAAA==.Rasar:BAABNQAECoEaAAIFAAgKURVdlAA7AgAFAAgKURVdlAA7AgAAAA==.Rathew:BAABNQAECoEUAAMEAAgKKB2cPgA8AgAEAAcK5B2cPgA8AgAIAAEKphgHBwFFAAAAAA==.Rawnext:BAAANQAECgYIEwAAAA==.',
Re='Revenger:BAAANQABCgMIAgAAAA==.Revoker:BAABNQAECoE+AAMDAAgK4RNDWgA8AgADAAgKExNDWgA8AgABAAcK+gxbNgBvAQAAAA==.',
Rh='Rhidge:BAAANQADCgYIBgAAAA==.',
Ri='Riddlez:BAABNQAECoEpAAMLAAgK9iUpCQBoAwALAAgK9iUpCQBoAwAcAAUKsCKbBwDhAQAAAA==.Riott:BAAANQABCgQIAwAAAA==.',
Ro='Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECgUIBwAAAA==.Rox:BAAANQAECgYIDQAAAA==.Royal:BAAANQADCgcIDAAAAA==.Royle:BAAANQAECgEIAgAAAA==.Roysham:BAAANQAECgQICQAAAA==.Roywar:BAAANQAECgEIAgAAAA==.',
['Ré']='Réîgn:BAABNQAECoEVAAIJAAcKpRRHUwCdAQAJAAcKpRRHUwCdAQAAAA==.',
Sa='Sacrus:BAAANQAECgUICQAAAA==.Samael:BAAANQADCgYIBgAAAA==.Sarah:BAABNQAECoEYAAMBAAkKcyILEADXAgABAAkKcyILEADXAgADAAEKcxALMQFAAAAAAA==.',
Sc='Scalelord:BAAANQADCgYJCwABNQADCggIDAAGAAAAAA==.Scoobear:BAAANQAECgMIBwABNQAECggIGAANAEIVAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senisia:BAAANQAECgQIBAAAAA==.Senjougahara:BAACNQAFFIETAAIRAAYKcB53AQAcAgARAAYKcB53AQAcAgA1AAQKgS0AAhEACQrzI4QJAD8DABEACQrzI4QJAD8DAAAA.Seriyah:BAACNQAFFIEFAAIhAAIKkgUwAwCDAAAhAAIKkgUwAwCDAAA1AAQKgSMAAiEACQoPGU8HAMACACEACQoPGU8HAMACAAAA.Serph:BAAANQAECgcICQABNQAECgcIGAAiAEMUAA==.',
Sh='Shabane:BAABNQAECoEcAAIeAAcKCx3iCgBFAgAeAAcKCx3iCgBFAgAAAA==.Shame:BAABNQAECoEtAAIWAAkKKxkVFAClAgAWAAkKKxkVFAClAgAAAA==.Shankey:BAAANQADCgYIBgAAAA==.Shasta:BAAANQADCgQIBAAAAA==.Shinobi:BAABNQAECoEXAAIOAAYKVxQkLwBpAQAOAAYKVxQkLwBpAQAAAA==.Shirls:BAABNQAECoEdAAICAAgKmxrmMgB9AgACAAgKmxrmMgB9AgAAAA==.Shivak:BAABNQAECoEtAAIfAAkKBRggBAC1AgAfAAkKBRggBAC1AgAAAA==.Shivanie:BAAANQAECgQICwAAAA==.Shock:BAAANQAECgQIDAAAAA==.Shredderella:BAABNQAECoEeAAIjAAgKkx5aGwB5AgAjAAgKkx5aGwB5AgAAAA==.Shrug:BAABNQAECoEbAAIZAAgKzBcSaQA1AgAZAAgKzBcSaQA1AgAAAA==.Shubie:BAAANQABCgIIAgABNQADCgUICwAGAAAAAA==.',
Si='Sicwiddit:BAAANQAECgUICQAAAA==.',
Sk='Skeeda:BAAANQAECgQIBwAAAA==.Skylinex:BAABNQAECoEWAAIkAAkK6hHWEQBSAgAkAAkK6hHWEQBSAgAAAA==.Skylinez:BAAANQAECgUICQAAAA==.Skïttles:BAABNQAECoEYAAQiAAcKQxTcJADOAQAiAAcKQxTcJADOAQAUAAEKAQkxowAvAAAPAAEKwgGIWgAdAAAAAA==.',
Sl='Sleezball:BAAANQAECgYIEAAAAA==.Sloppyslice:BAAANQAECgEIAQAAAA==.',
So='Softie:BAAANQAECgEIAQABNQAECgkJHQAZAHwXAA==.Sonictide:BAAANQAECgUICgAAAA==.Soulscream:BAABNQAECoEhAAILAAkKdh46FwAEAwALAAkKdh46FwAEAwAAAA==.',
Sp='Spaghetto:BAABNQAECoEkAAIUAAgKWRsMJQCJAgAUAAgKWRsMJQCJAgAAAA==.Sprite:BAAANQADCgQJBAAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgcIDwAAAA==.Strive:BAAANQADCgIIAgAAAA==.Stumpchuggns:BAAANQAECgMIBAAAAA==.',
Su='Suzel:BAAANQADCggIEgAAAA==.',
Sy='Sydaria:BAAANQABCgIIAgAAAA==.Synder:BAABNQAECoEiAAIfAAgKXAblDQA/AQAfAAgKXAblDQA/AQAAAA==.',
Ta='Tainin:BAABNQAECoEdAAIEAAcKSyVHGgDsAgAEAAcKSyVHGgDsAgAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQAECgEIAgAAAA==.Tarynna:BAABNQAECoEdAAIaAAcKWA+ViACiAQAaAAcKWA+ViACiAQAAAA==.Tazdingobomb:BAAANQAECgEIAgAAAA==.Tazerface:BAABNQAECoEaAAMQAAgKcAz3DQChAQAQAAgKcAz3DQChAQAFAAYKjgSuPgEBAQAAAA==.',
Te='Tekin:BAABNQAECoEiAAICAAgKDxTjTAAWAgACAAgKDxTjTAAWAgAAAA==.Teleprompter:BAAANQAECgQICAAAAA==.Telrissan:BAABNQAECoEUAAIFAAcKLRw7igBQAgAFAAcKLRw7igBQAgAAAA==.Tenkawnor:BAAANQADCggIDgAAAA==.Tenyroldemon:BAABNQAECoEjAAIVAAgKFyHcAwDyAgAVAAgKFyHcAwDyAgAAAA==.',
Th='Thald:BAABNQAECoEiAAIeAAgKJhftDAAPAgAeAAgKJhftDAAPAgAAAA==.Thaznotmilk:BAAANQADCgQIBAAAAA==.',
Ti='Timzilla:BAAANQADCgcIBwABNQAECggIJAAKAF8hAA==.Tinytip:BAAANQADCgYIBgAAAA==.Tisakna:BAABNQAECoEwAAMFAAkKQiRVPwD5AgAFAAgKICNVPwD5AgAQAAMKiiOGFgAkAQAAAA==.Titanus:BAAANQAECgEIAQAAAA==.',
To='Togon:BAAANQAECggIAgAAAA==.Tooezy:BAAANQAECgIIAwAAAA==.Tool:BAAANQAECgMIBQAAAA==.Tostitos:BAAANQADCggICwAAAA==.',
Tr='Tralgina:BAAANQAECgYICwABNQAECgkJLQAHABUdAA==.Trask:BAABNQAECoEeAAIFAAgKohNGogAdAgAFAAgKohNGogAdAgAAAA==.Trogdoor:BAAANQAECgIIAwAAAA==.Trokom:BAACNQAFFIEHAAIFAAQK8CWTEQDCAQAFAAQK8CWTEQDCAQA1AAQKgSsAAgUACQqvJoEBAPIDAAUACQqvJoEBAPIDAAE1AAUUBAoHAAUA8CUA.Trokopally:BAAANQAECgYIBgABNQAFFAQKBwAFAPAlAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAABNQAECoElAAMaAAgK7g3vfQC/AQAaAAgK7g3vfQC/AQAbAAMKiwfCTQCKAAAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ul='Ullrian:BAAANQAECggICAAAAA==.',
Un='Uncletrump:BAAANQADCgYIBgAAAA==.',
Ur='Urbanmech:BAABNQAECoEdAAMOAAgKSh5tFQCAAgAOAAgKSh5tFQCAAgAeAAEKyAR0LgAoAAAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECgkJMAAiAI4TAA==.Vandermark:BAABNQAECoEwAAUiAAkKjhOiFwBdAgAiAAkKjhOiFwBdAgAhAAQKLRHwHgDuAAAUAAQKoQpbewC1AAAPAAIKIBvRNgCmAAAAAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Viaos:BAAANQAECgUIEAAAAA==.Vidrus:BAAANQAECgEIAQAAAA==.Vilkas:BAAANQAFFAEIAQABNQAECgkJFgAWAD4hAA==.Viserion:BAAANQADCgYIEgAAAA==.',
Vu='Vulpinor:BAAANQAECgEIAQAAAA==.',
Wa='Waddledoo:BAABNQAECoEgAAIEAAgKkx+IJAC0AgAEAAgKkx+IJAC0AgAAAA==.Warmaku:BAABNQAECoEWAAIiAAcK4B7HFwBcAgAiAAcK4B7HFwBcAgAAAA==.',
Wh='Whïteoak:BAAANQAECgcIEwAAAA==.',
Wi='Wienz:BAAANQADCgMIAwAAAA==.Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAABNQAECoEdAAIKAAkKCiCEEwD6AgAKAAkKCiCEEwD6AgAAAA==.Xanyp:BAAANQAECgEJBQABNQAECgkJHQAKAAogAA==.',
Xe='Xeletath:BAAANQAECgEIAQAAAA==.Xerg:BAAANQAECgEIAQABNQAECggIJAAeAH4aAA==.',
Xi='Xinaveruk:BAAANQAECgcICQAAAA==.',
Xo='Xoro:BAAANQAECgQICAAAAA==.',
Xr='Xrxyz:BAAANQAECggICAAAAA==.',
Xs='Xshamster:BAABNQAECoEpAAMEAAkKVBqBIwC6AgAEAAkKVBqBIwC6AgAIAAEKdxR4EAE4AAAAAA==.',
Ye='Yewna:BAAANQAECgIIAwABNQAECgkJMAAEAKskAA==.',
Za='Zaarf:BAAANQADCgYIBgAAAA==.Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgcIDQAAAA==.Zachpri:BAAANQAECgEIAgAAAA==.Zanyr:BAAANQADCgMIAQABNQAECgkJHQAKAAogAA==.Zau:BAABNQAECoEeAAMdAAgKABxoBQBJAgAdAAcKKx1oBQBJAgAaAAQKPxMD1gDxAAAAAA==.',
Zo='Zodiac:BAAANQADCgUIBQABNQAECgkJIQAFACUiAA==.Zolja:BAAANQAECgMICAAAAA==.Zoney:BAAANQAECgIIAwAAAA==.Zordlon:BAAANQAECgYIDwAAAA==.',
Zu='Zukem:BAABNQAECoEhAAIDAAgKgiKjJADmAgADAAgKgiKjJADmAgAAAA==.Zulelphie:BAAANQADCgMIBAAAAA==.Zuli:BAAANQAECgEIAQABNQAECgQIBAAGAAAAAA==.',
Zy='Zyariah:BAAANQADCgYICwAAAA==.Zyvea:BAABNQAECoEYAAIZAAgKahiOWwBcAgAZAAgKahiOWwBcAgAAAA==.',
['Çr']='Çrossblesser:BAAANQAECgEIAQAAAA==.',
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
