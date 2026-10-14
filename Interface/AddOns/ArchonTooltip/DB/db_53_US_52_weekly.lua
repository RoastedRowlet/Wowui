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

local lookup = {'Warlock-Demonology','Hunter-Marksmanship','Paladin-Holy','Hunter-BeastMastery','Shaman-Restoration','Mage-Arcane','Rogue-Assassination','Paladin-Protection','Unknown-Unknown','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','DemonHunter-Devourer','Paladin-Retribution','Monk-Windwalker','Druid-Guardian','Mage-Frost','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Druid-Balance','DemonHunter-Vengeance','Priest-Shadow','DemonHunter-Havoc','Warrior-Protection','Warrior-Arms','Warlock-Destruction','Rogue-Outlaw','Rogue-Subtlety','Priest-Discipline','Warlock-Affliction','Monk-Brewmaster','Evoker-Augmentation','Druid-Feral','Druid-Restoration','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acidsword:BAABNQAECn8aAAIBAAgKcBxnNAC1AgABAAgKcBxnNAC1AgABNQAFFAIIBgACABwUAA==.',
Ad='Adaria:BAAANQADCgMIAwAAAA==.Adder:BAAANQADCgIIAgAAAA==.Adelgeise:BAAANQAECgQIBAABNQAECgkJNgADALAjAA==.Adrua:BAAANQAECgQIBQAAAA==.Adym:BAABNQAECn8gAAIEAAgKhxJVewAUAgAEAAgKhxJVewAUAgAAAA==.',
Ag='Agave:BAABNQAECn8rAAIFAAkKJhAIXgDxAQAFAAkKJhAIXgDxAQAAAA==.',
Ai='Aiyah:BAAANQAECgQICAAAAA==.',
Al='Altarboi:BAAANQAECgUICwAAAA==.Alüçard:BAABNQAECn8XAAIGAAYKCwwyHQFXAQAGAAYKCwwyHQFXAQAAAA==.',
Am='Amoraniel:BAABNQAECn8nAAIGAAgK4xwubwCfAgAGAAgK4xwubwCfAgAAAA==.',
An='Anavar:BAAANQAECgYIBgAAAA==.Andrar:BAAANQADCgYIBwAAAA==.Andres:BAABNQAECn8UAAIHAAgKDRrzIQByAgAHAAgKDRrzIQByAgAAAA==.Andresra:BAABNQAECn8oAAIGAAgKLSDoZAC0AgAGAAgKLSDoZAC0AgABNQAECggIFAAHAA0aAA==.Anie:BAAANQADCgQIBAAAAA==.',
Ar='Arararagi:BAAANQADCggICAAAAA==.Arelà:BAAANQAECgQIDQAAAA==.Arrowsnag:BAAANQADCgQIBQAAAA==.Arthusxoxo:BAAANQAECggIBgAAAA==.',
As='Asrael:BAAANQAECgYIBgABNQAECgkJIgAIABkWAA==.Asterin:BAAANQADCgUICwAAAA==.',
Au='Augtism:BAAANQAECgIIAgABNQAECggIEgAJAAAAAA==.',
Av='Avâtre:BAABNQAECn8bAAIKAAcK9BcvWgARAgAKAAcK9BcvWgARAgAAAA==.',
Az='Azlea:BAAANQADCgcIBwAAAA==.',
Ba='Baguette:BAAANQAECgUIDAAAAA==.Bajingobomb:BAABNQAECn8qAAMLAAgKhiGtGwDkAgALAAgKPCGtGwDkAgAMAAYKER2vSgDJAQAAAA==.Bakblood:BAAANQABCgYICgAAAA==.Bakshung:BAAANQADCgYIBgAAAA==.Barkruffalo:BAAANQADCgEIAQAAAA==.Barndoogle:BAAANQADCgMIAwAAAA==.Barnpall:BAAANQAECgYICAAAAA==.Barrybonds:BAAANQADCggIDAAAAA==.Bayao:BAAANQAECgUICAAAAA==.',
Be='Be:BAABNQAECn8gAAINAAcKVxmUXwD/AQANAAcKVxmUXwD/AQAAAA==.Beckyoncé:BAABNQAECn8qAAIOAAkKGCN0BACMAwAOAAkKGCN0BACMAwAAAA==.Bedris:BAABNQAECn8eAAQIAAcKFRf7IgDGAQAIAAcKFRf7IgDGAQAPAAYK4gkz+QAlAQADAAEKXQJHNAEfAAAAAA==.Beerticus:BAABNQAECn8iAAIQAAcKHxzWHABNAgAQAAcKHxzWHABNAgAAAA==.',
Bi='Biar:BAAANQADCgEIAQAAAA==.Bigdingus:BAABNQAECn8ZAAIRAAgKmRu+DwBfAgARAAgKmRu+DwBfAgAAAA==.Binggles:BAACNQAFFH8oAAMGAAcKDCbpAQDcAgAGAAcK7CPpAQDcAgASAAIKiiXBAwDbAAA1AAQKfyMAAgYACQpgJecfAFoDAAYACQpgJecfAFoDAAAA.',
Bl='Blacksheep:BAAANQAECgIIAgAAAA==.Blazze:BAAANQAECgUICgABNQAECgkJGAAEAC0cAA==.Blôôðhôôf:BAAANQADCgQIBAAAAA==.',
Bo='Bokinar:BAAANQAECggICAAAAA==.Bomboclaat:BAAANQAECgIIBgABNQAECgkJJAAQABckAA==.Boolay:BAAANQAECgYIEgABNQABCgUIBQAJAAAAAA==.Boomcommand:BAAANQADCgEIAgAAAA==.Boosteyboy:BAAANQAECgYICgAAAA==.Boozing:BAAANQADCgMIAwABNQAECgkJIgAEANQgAA==.Bosmina:BAABNQAECn80AAINAAkK/BowNQCQAgANAAkK/BowNQCQAgAAAA==.',
Br='Braei:BAABNQAECn8gAAIDAAcKlhOIcADDAQADAAcKlhOIcADDAQAAAA==.Brandyth:BAAANQADCgEIAQAAAA==.Breakinbones:BAAANQADCgEIAQAAAA==.Breelynn:BAAANQADCggICAAAAA==.Brenhunt:BAAANQADCggIFAAAAA==.Brenmonk:BAABNQAECn8fAAIQAAcK8gp9NQBkAQAQAAcK8gp9NQBkAQAAAA==.Brenpriest:BAAANQADCgYIBgAAAA==.Brenshammy:BAAANQADCgcIDAAAAA==.Bruenor:BAAANQAECgMIAwAAAA==.',
Bu='Bubblebaddie:BAAANQAECgMIBQAAAA==.Bubblicous:BAAANQADCgYIBgAAAA==.Bugenhagen:BAABNQAECn80AAIFAAkKqyQoBwCHAwAFAAkKqyQoBwCHAwAAAA==.Butchers:BAAANQAECgUIBgAAAA==.Buttpaladin:BAABNQAECn8nAAIPAAgK2BY/kAD/AQAPAAgK2BY/kAD/AQAAAA==.',
Ca='Caliden:BAAANQABCgYICwAAAA==.Cardib:BAACNQAFFH8QAAMLAAcKUxsWBwCoAQALAAUKeSIWBwCoAQATAAMKmhCHDgDqAAA1AAQKfygAAwsACQrTJesGAI4DAAsACQqxJesGAI4DABMAAwoVJBlaADoBAAAA.Cavos:BAABNQAECn8dAAIOAAcKgRsYJwAIAgAOAAcKgRsYJwAIAgAAAA==.',
Ce='Centradin:BAAANQAECgIIBAAAAA==.Cernsarn:BAABNQAECn8oAAIMAAkKwBbrKQByAgAMAAkKwBbrKQByAgAAAA==.',
Ch='Chantorc:BAAANQADCgIIAgAAAA==.Chiri:BAECNQAFFH8GAAMUAAQKHwmyFACEAAAUAAMKUgGyFACEAAAVAAIKQwYFDQB6AAA1AAQKfyIAAxUACQqBEtgTAA4CABUACQqBEtgTAA4CABQAAwoSA0dEAHoAAAAA.Chvngus:BAABNQAECn8qAAIPAAkKNCCRLAATAwAPAAkKNCCRLAATAwAAAA==.',
Ci='Citizencain:BAAANQAECgQIDwAAAA==.',
Cl='Claytnbigsby:BAAANQAECgMIBwAAAA==.',
Co='Cocheeze:BAAANQAECgYIBgAAAA==.Cogswell:BAAANQADCggIEgAAAA==.Condor:BAEANQAECggICwAAAA==.Conmammoth:BAAANQAECgUICQAAAA==.Coohwhip:BAAANQAECgEIAQAAAA==.Cornorgan:BAAANQAECgcIEAAAAA==.Corèl:BAAANQADCgUIBwAAAA==.Cowbut:BAAANQADCgEIAQAAAA==.',
Cr='Crakidos:BAAANQADCgQJBAAAAA==.Crambone:BAAANQABCgIIAgAAAA==.Crinaa:BAABNQAECn8eAAIWAAkKVRKVNABAAgAWAAkKVRKVNABAAgAAAA==.Cristobal:BAAANQAECgUIBAAAAA==.Crunkshot:BAAANQADCgMIBAAAAA==.',
Cu='Curaga:BAAANQAECgMIAwAAAA==.Curnsarn:BAAANQAECgQIBAABNQAECgkJKAAMAMAWAA==.',
Cy='Cydea:BAAANQAECgQIBwAAAA==.',
Da='Dagidan:BAABNQAECn8xAAIXAAkKGxJVDAD+AQAXAAkKGxJVDAD+AQAAAA==.Darktide:BAAANQAECggIEAAAAA==.Dashawmon:BAAANQADCggICAABNQADCgYICQAJAAAAAA==.Dashel:BAAANQAECgYIDAABNQAECgkJKwAYACASAA==.',
De='Dead:BAAANQADCggICAAAAA==.Deathtoxi:BAAANQAECgIIAQAAAA==.Degey:BAAANQADCgIIAgAAAA==.Demontotems:BAAANQADCgYIBgAAAA==.Demotoxi:BAABNQAECn8kAAQOAAkKHx2YEgDUAgAOAAkKHx2YEgDUAgAZAAQKUBkzYAD1AAAXAAIKzQoCLABRAAAAAA==.Deriso:BAAANQAECggIEgAAAA==.Dertbirtbek:BAAANQADCgMIAwABNQADCggIDAAJAAAAAA==.Destrozinth:BAAANQAECgcICwAAAA==.Dethorok:BAABNQAECn8uAAIEAAkKJCVXBQC4AwAEAAkKJCVXBQC4AwAAAA==.Deuce:BAAANQABCgIJAQAAAA==.Deåth:BAAANQADCgYIDQABNQAECgEIAQAJAAAAAA==.',
Di='Diagonpally:BAAANQADCgYIDgABNQAECgkJNAAFAKskAA==.Dib:BAAANQAECgQICgAAAA==.Digey:BAABNQAECn8hAAMaAAgKPSOtBAA1AwAaAAgKPSOtBAA1AwAbAAEKAAAVTQE1AAAAAA==.Direwolf:BAAANQADCgYIBgAAAA==.Divah:BAAANQAECgYIDgAAAA==.',
Do='Dontlookatme:BAAANQABCgUIBQAAAA==.Dopeaf:BAAANQADCgcIDAAAAA==.Dottër:BAAANQADCggIEwABNQAECgEIAQAJAAAAAA==.',
Dr='Drakbek:BAAANQAECgYIDwAAAA==.Dreadshot:BAAANQADCgYIBgAAAA==.Dreamshift:BAAANQADCgYICAAAAA==.Dronebot:BAABNQAECn9TAAIYAAkKUx2bDgAEAwAYAAkKUx2bDgAEAwAAAA==.Drucifer:BAAANQADCggIDwAAAA==.',
Du='Dud:BAAANQAECgYIBgABNQAECgcIEQAJAAAAAA==.Durros:BAABNQAECn8bAAIFAAgKPBhwSQA6AgAFAAgKPBhwSQA6AgAAAA==.Dustyshotz:BAAANQAECgQIBAAAAA==.',
Dy='Dyhanna:BAAANQAECggIBwAAAA==.',
Eb='Eboger:BAAANQAECgIIAgAAAA==.',
Eg='Egam:BAAANQAECgUIBQAAAA==.',
El='Elunelphie:BAAANQADCgYIBwAAAA==.',
Em='Embody:BAABNQAECn8eAAIWAAcKKw5HVgB6AQAWAAcKKw5HVgB6AQAAAA==.Emiree:BAAANQAECgIIAgAAAA==.',
En='Endlyss:BAABNQAECn8bAAIPAAkKvBm5VwCMAgAPAAkKvBm5VwCMAgAAAA==.',
Er='Erasmas:BAABNQAECn82AAMDAAkKsCNBBgCZAwADAAkKsCNBBgCZAwAPAAcKlBpDkgD7AQAAAA==.Erzascarlét:BAABNQAECn80AAIIAAkKjB4gCwDmAgAIAAkKjB4gCwDmAgAAAA==.',
Es='Essentia:BAAANQABCgEIAQAAAA==.',
Eu='Euphoricx:BAAANQAECgYICwAAAA==.',
Ev='Evildeader:BAAANQAECggIDwAAAA==.Eviltotems:BAAANQAECgcIEgABNQAECggIDwAJAAAAAA==.',
Ex='Excell:BAAANQADCgEIAQAAAA==.',
Fa='Facesmasher:BAAANQADCgIIAgAAAA==.Falgur:BAABNQAECn8uAAMKAAkKiR/9GgAlAwAKAAkKiR/9GgAlAwAFAAIKQAs7+gBwAAAAAA==.Fantasma:BAAANQAECgEIAQAAAA==.',
Fe='Fear:BAAANQAECgIIAgAAAA==.',
Fi='Findal:BAAANQADCggICQABNQABCgUIBwAJAAAAAA==.Fistymoo:BAEANQADCgMIAwABNQAFFAQIBgAUAB8JAA==.Fivemagics:BAABNQAECn8lAAMBAAkKVxOGYgAuAgABAAgK+xKGYgAuAgAcAAIKexTcVQB8AAAAAA==.',
Fl='Fleaboy:BAABNQAECn8XAAMdAAgKHhGoCQDqAQAdAAgKHhGoCQDqAQAeAAEKSwRRUAA6AAAAAA==.Flist:BAABNQAECn8kAAIQAAkKFyR2AwCeAwAQAAkKFyR2AwCeAwAAAA==.Floof:BAAANQADCgYIDwAAAA==.',
Fo='Foe:BAAANQAECgUIEQAAAA==.Fortlock:BAAANQADCgIIAgAAAA==.',
Fr='Frankyice:BAABNQAECn8eAAIYAAcKSBdtJwDsAQAYAAcKSBdtJwDsAQAAAA==.Freesia:BAAANQAECgIIAgAAAA==.Fruitjuice:BAAANQAECgYIDAAAAA==.',
Fx='Fxce:BAAANQAFFAEIAQAAAA==.',
['Fâ']='Fâmine:BAAANQADCggICAAAAA==.',
Ga='Gaothan:BAAANQAECgEIAQAAAA==.',
Ge='Genjy:BAAANQABCgIIAgAAAA==.',
Gh='Ghulz:BAAANQAECgcIEgAAAA==.',
Gi='Gibsmedats:BAABNQAECn8pAAIZAAgK/xK6NAADAgAZAAgK/xK6NAADAgAAAA==.',
Gl='Glaiven:BAABNQAECn8eAAIOAAgKHBPjKgDnAQAOAAgKHBPjKgDnAQAAAA==.Glasscleaner:BAABNQAECn8WAAIDAAkKJiPJCgBxAwADAAkKJiPJCgBxAwABNQAFFAYIFAAUAGMbAA==.Glenmorangie:BAABNQAECn8fAAMfAAkKLh+pBAB4AgAfAAcKnx+pBAB4AgAYAAYKrxzfJQD8AQAAAA==.',
Gn='Gnartusk:BAABNQAECn8kAAIMAAcK8iH+HwCxAgAMAAcK8iH+HwCxAgAAAA==.',
Go='Goober:BAAANQADCgEIAQABNQAECgUICQAJAAAAAA==.',
Gr='Grawlso:BAAANQADCgYIBgAAAA==.Greens:BAABNQAECn8rAAIWAAkKthmwHADhAgAWAAkKthmwHADhAgAAAA==.Greenz:BAAANQADCgIIAgAAAA==.Gremory:BAAANQADCgYJCwABNQADCggIDAAJAAAAAA==.Grillvy:BAAANQADCgIIBgAAAA==.Grumbo:BAAANQAECgEIAQABNQAECgQIBwAJAAAAAA==.Grïma:BAABNQAECn8sAAMgAAkKdRo+BACdAgAgAAgKaB0+BACdAgABAAMKVxAKBAG9AAAAAA==.',
Gs='Gsus:BAAANQADCggICAABNQAECggILAAhANYcAA==.',
Gu='Gueritestje:BAABNQAECn8mAAIIAAgKLiC+CgDtAgAIAAgKLiC+CgDtAgAAAA==.Guzzlord:BAABNQAECn8eAAQUAAgKyghNJwB7AQAUAAgKyghNJwB7AQAVAAQKQQbqLAC2AAAiAAQKbQcVGQCnAAAAAA==.',
Ha='Halfman:BAAANQAECgEIAQAAAA==.Handsomejack:BAAANQAECgEIAgABNQAECggIKgALAIYhAA==.Hanekawa:BAAANQAECggIAQABNQAECggIAgAJAAAAAA==.Harfnar:BAAANQABCggICAABNQADCgEIAQAJAAAAAA==.',
Hb='Hboozing:BAABNQAECn8iAAMEAAkK1CAiEwBRAwAEAAkK1CAiEwBRAwACAAEKkxJpgQA8AAAAAA==.',
He='Healyhavok:BAAANQADCgIIAgAAAA==.Heayt:BAAANQABCgIIBAAAAA==.Heleous:BAAANQADCgMIAwABNQADCgYIBgAJAAAAAA==.',
Hi='Hikari:BAAANQADCgUIBQAAAA==.Hipdrop:BAAANQAECgMIAwAAAA==.Hitoshura:BAABNQAECn8cAAMTAAkKqSSYBgB3AwATAAkK8COYBgB3AwALAAcK+iTbGgDpAgAAAA==.Hittnrunn:BAAANQAECgEIAQAAAA==.',
Ho='Holyginger:BAAANQAECgUICgAAAA==.Holyglizzy:BAABNQAECn8YAAIPAAgKHxSqkwD4AQAPAAgKHxSqkwD4AQAAAA==.Holymajìk:BAAANQABCgIIAwAAAA==.Holytoxi:BAAANQADCgEIAQABNQAECgkJJAAOAB8dAA==.',
Hy='Hypérîon:BAAANQAECgQIBQAAAA==.',
Ia='Iagging:BAAANQAECgcJEgABNQAFFAYIFAAUAGMbAA==.',
Ic='Ichtaca:BAAANQADCgEIAQAAAA==.',
Ik='Ikiryo:BAEANQAECgIIBgAAAA==.',
Im='Imtuggdup:BAABNQAECn8gAAMGAAkK8x5qNgAcAwAGAAkK8x5qNgAcAwASAAEKAABxRAA4AAAAAA==.Imzachedup:BAAANQADCgYICAAAAA==.',
In='Infidel:BAABNQAECn8wAAIWAAkKeyQ+BgCiAwAWAAkKeyQ+BgCiAwAAAA==.Invert:BAAANQAECgQIBAAAAA==.',
Ip='Ippiekiyaymf:BAAANQAECgEIAwAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQAAAA==.',
Ir='Irayne:BAAANQADCgQIBAAAAA==.Irisharcher:BAAANQAECgEIAQAAAA==.Irishbeauty:BAAANQADCgcIBwAAAA==.Irishfury:BAAANQADCgIIAgAAAA==.Irishman:BAAANQAECgQIBAAAAA==.',
Is='Isengardd:BAAANQAECgEIAQAAAA==.',
It='Itazki:BAABNQAECn8hAAMjAAkKAx9MBABIAwAjAAkKAx9MBABIAwAWAAEKHQySsgAuAAAAAA==.',
Ja='Jackpot:BAAANQADCgEIAQAAAA==.Jaft:BAAANQADCgYIEAAAAA==.Jalter:BAACNQAFFH8UAAIUAAYKYxs6BAAyAgAUAAYKYxs6BAAyAgA1AAQKfx8AAhQACQrVIv4DAHIDABQACQrVIv4DAHIDAAAA.Janha:BAAANQADCggICQAAAA==.',
Je='Jediknight:BAAANQAECgMIBAAAAA==.Jenga:BAAANQAECgcIDAAAAA==.Jergal:BAABNQAECn8XAAIbAAgKNAoNsACfAQAbAAgKNAoNsACfAQAAAA==.Jertdor:BAAANQADCgQIBAAAAA==.',
Jf='Jf:BAABNQAECn8sAAMPAAkKHxr+eQAzAgAPAAgKnhj+eQAzAgADAAkKswpeagDVAQAAAA==.',
Ji='Jibbage:BAAANQAECgQIBAABNQAECgkJMAAWAHskAA==.Jinkala:BAAANQABCgYIBwAAAA==.Jitzakkal:BAACNQAFFH8aAAMBAAcKXSXWBAAqAgABAAUKaSTWBAAqAgAcAAIKyyYAAwDmAAA1AAQKfyEAAxwACQoMJq0KAEwCAAEABwp7JQs5AKYCABwABgpkJK0KAEwCAAAA.',
Jn='Jn:BAAANQADCgcIDAAAAA==.',
Jo='Johnpaladin:BAABNQAECn8oAAIPAAkKByZ+BwC9AwAPAAkKByZ+BwC9AwAAAA==.Joshswims:BAABNQAECn8VAAITAAYK5RsYQgC3AQATAAYK5RsYQgC3AQAAAA==.',
Js='Js:BAAANQADCgYICwAAAA==.',
Ju='Juendi:BAAANQAECgIIAgABNQAECgkJNAAGAPQjAA==.Juleita:BAAANQABCgQIBAAAAA==.Jumbojoe:BAAANQAECgIIAgAAAA==.',
Ka='Kait:BAAANQADCgQIBgAAAA==.Kapena:BAAANQAECggIDwAAAA==.Kardinal:BAABNQAECn8xAAQBAAkKwSOcBQCiAwABAAkKwSOcBQCiAwAcAAUKSBpjHwBzAQAgAAEKAABUKgBCAAAAAA==.Kargan:BAAANQADCgcICAABNQAECgUIDQAJAAAAAA==.Karliee:BAAANQADCggICAABNQAECgIIAgAJAAAAAA==.Karpathous:BAAANQAECggIBAAAAA==.',
Ke='Keladorn:BAABNQAECn8gAAIPAAcKLSLkRgC9AgAPAAcKLSLkRgC9AgAAAA==.',
Kh='Khanyiso:BAABNQAECn8iAAIIAAkKGRZxFABeAgAIAAkKGRZxFABeAgAAAA==.Kharak:BAABNQAECn8dAAIGAAcKHiHojgBhAgAGAAcKHiHojgBhAgABNQABCgUIBwAJAAAAAA==.',
Ki='Kichi:BAAANQADCgQIBAAAAA==.Kichii:BAAANQAECgQICAAAAA==.Kieran:BAABNQAECn8rAAMYAAkKIBICLQC6AQAYAAcKdw4CLQC6AQANAAQK2gfMugDjAAAAAA==.Kilsaurys:BAACNQAFFH8FAAIWAAIKyQuTHwCSAAAWAAIKyQuTHwCSAAA1AAQKfykABBYACQonG24kAKsCABYACQonG24kAKsCACQABwqvEhYsALgBABEABQqzDac6ANEAAAAA.Kirakishou:BAAANQAECggIAgAAAA==.Kismete:BAABNQAECn8ZAAMiAAgKyQ53CwCkAQAiAAgKyQ53CwCkAQAVAAEKAACAQQAmAAAAAA==.',
Ko='Konstantine:BAABNQAECn8ZAAMPAAcKpB4+ZQBnAgAPAAcKpB4+ZQBnAgAIAAUKuBTCOwAPAQAAAA==.',
Kr='Kravnoc:BAAANQADCgcIDQAAAA==.Krittykitkat:BAAANQAECgIIAgABNQAECgYIBgAJAAAAAA==.Kryptocron:BAAANQAECgMIAwAAAA==.',
Kw='Kwazlock:BAAANQADCgEIAQAAAA==.',
Ky='Kysoti:BAAANQADCgQIBAAAAA==.',
['Kí']='Kítsune:BAAANQAECgQIBgAAAA==.',
La='Laprimera:BAAANQAECgEIAQAAAA==.Lasticon:BAABNQAECn8ZAAIEAAYKBwgc2gBHAQAEAAYKBwgc2gBHAQAAAA==.Lazyjade:BAABNQAECn8mAAIYAAkKoRh6GQCAAgAYAAkKoRh6GQCAAgAAAA==.',
Le='Lenarius:BAAANQABCgUJBQABNQABCgYIBgAJAAAAAA==.Leonidass:BAAANQADCgUIBQAAAA==.Leprechauñ:BAAANQADCgQIBAAAAA==.Leyline:BAAANQADCgYICwAAAA==.',
Li='Lichborne:BAAANQADCgcIBwAAAA==.Lilgangster:BAAANQADCgIIAgAAAA==.',
Lo='Lockofdirish:BAAANQADCgcIDwAAAA==.Lorfirandor:BAAANQADCgYIDAAAAA==.Lorynn:BAABNQAECn8jAAIGAAkKqB06RwD1AgAGAAkKqB06RwD1AgAAAA==.',
Ma='Maches:BAAANQAECgQIBgAAAA==.Madwe:BAABNQAECn8bAAILAAgKaw7ZVgCyAQALAAgKaw7ZVgCyAQAAAA==.Magturri:BAABNQAECn8qAAMEAAgKnh6wQgChAgAEAAgKnh6wQgChAgACAAIKLwdceQBWAAAAAA==.Majìkstik:BAAANQABCgIIAgAAAA==.Mamameatmode:BAAANQAECgUIBwAAAA==.Marlbororeds:BAAANQAECgYICgAAAA==.Maxfirepower:BAAANQADCggIIAAAAA==.Maxfrogpower:BAAANQADCgcIDAAAAA==.Maxsunward:BAAANQAECgQIDQAAAA==.',
Me='Meepasaurus:BAABNQAECn8pAAIaAAgKwyDDBwDYAgAaAAgKwyDDBwDYAgAAAA==.Megaforce:BAAANQAECgEIAQAAAA==.Mellky:BAABNQAECn8sAAIlAAkKNiTuAgCHAwAlAAkKNiTuAgCHAwAAAA==.Metanoia:BAABNQAECn8cAAIHAAgKbR/rGACxAgAHAAgKbR/rGACxAgABNQAECgkJMQABAMEjAA==.',
Mg='Mgamer:BAAANQADCgYIBgAAAA==.',
Mi='Mib:BAEBNQAECn8ZAAILAAkKVhxpJwCbAgALAAkKVhxpJwCbAgABNQAECggICwAJAAAAAA==.Mibb:BAEBNQAECn8nAAIGAAkKECHiPgAIAwAGAAkKECHiPgAIAwABNQAECggICwAJAAAAAA==.Midnitetrvlr:BAABNQAECn8YAAILAAgK0gzzYgCBAQALAAgK0gzzYgCBAQAAAA==.Migothedruid:BAAANQADCgEIAQAAAA==.Mirren:BAABNQAECn8gAAISAAgK3RWzCwAAAgASAAgK3RWzCwAAAgAAAA==.Missmoans:BAAANQADCgYICAABNQAECgcIHAAkAOAUAA==.',
Mo='Mokokofosho:BAAANQADCgMIAwAAAA==.Momojojo:BAABNQAECn8lAAIcAAkKohrgAgAjAwAcAAkKohrgAgAjAwAAAA==.Monre:BAAANQAECgMIBQABNQAECgcIEAAJAAAAAA==.Moonflame:BAABNQAECn8jAAINAAkKRRvmMACiAgANAAkKRRvmMACiAgAAAA==.Mooriah:BAABNQAECn8mAAIWAAkK/QQxXwBPAQAWAAkK/QQxXwBPAQAAAA==.Mordekhuul:BAABNQAECn8mAAIBAAkKpBxxJQDrAgABAAkKpBxxJQDrAgAAAA==.Motowa:BAAANQAECgIIBAAAAA==.Mournhide:BAAANQAECggICQAAAA==.',
Mp='Mpkshaman:BAAANQAFFAEIAQAAAA==.',
Mu='Muddbutt:BAAANQADCgQIBgAAAA==.',
My='Mycilya:BAAANQADCggICAAAAA==.Mynche:BAAANQADCgYJBgABNQAECgYIEAAJAAAAAA==.Mynchus:BAAANQAECgYIEAAAAA==.Mysterydh:BAABNQAECn8WAAIXAAgKwR5tBQDVAgAXAAgKwR5tBQDVAgAAAA==.Mysterypala:BAAANQAECgUICgAAAA==.Mysteryvoke:BAABNQAECn8eAAIUAAcKqiSZCwDpAgAUAAcKqiSZCwDpAgAAAA==.Mystodin:BAAANQAECgIIAQAAAA==.Myztic:BAAANQADCgEIAQAAAA==.',
Na='Naneko:BAAANQAECgYIEgAAAA==.',
Ne='Neelix:BAABNQAECn8aAAMEAAgKtgm7kADkAQAEAAgKtgm7kADkAQACAAUK+gGEZQCQAAAAAA==.Nehi:BAAANQAECggICQAAAA==.Neotahr:BAABNQAECn8xAAICAAkKKBGbJgATAgACAAkKKBGbJgATAgAAAA==.Neuron:BAEANQABCgUICgABNQAECgIIBgAJAAAAAA==.',
Ni='Nickiminajj:BAAANQAECggICAAAAA==.Nismoto:BAABNQAECn8rAAIEAAkKEhE5YwBNAgAEAAkKEhE5YwBNAgAAAA==.Nitehunter:BAAANQAECgYIEQAAAA==.',
No='Noobert:BAAANQAECgcIEwAAAA==.Novademic:BAAANQAECgUIDwAAAA==.',
['Nö']='Növacaïn:BAAANQAECgEIAQAAAA==.',
Of='Offseason:BAAANQADCgYIBgAAAA==.',
Og='Ognikkay:BAABNQAECn8uAAIjAAkKLx6qBQAaAwAjAAkKLx6qBQAaAwAAAA==.',
Or='Oranthør:BAAANQADCgUIBQAAAA==.Orcpriest:BAAANQADCgcIBwAAAA==.',
Oy='Oyakev:BAAANQADCgUIBgAAAA==.Oyea:BAAANQABCgIIAgABNQAECgkJJgAYAKEYAA==.',
Pa='Pabiloneta:BAAANQAECgYICAABNQAECggIFAAHAA0aAA==.Pakami:BAAANQAECgYIBgAAAA==.Pallyana:BAABNQAECn8iAAIPAAkKJxyPUgCaAgAPAAkKJxyPUgCaAgAAAA==.Palosdin:BAAANQAECgUIBwAAAA==.Papapump:BAAANQADCgQJBAAAAA==.Parsleyposh:BAAANQAECgQIBAABNQAECgQIBwAJAAAAAA==.Pass:BAAANQAECgUIBQABNQAECgkJJAAQABckAA==.',
Pe='Perridan:BAAANQAECgcIBwAAAA==.',
Ph='Phalandrel:BAABNQAECn8VAAIEAAkKaxTwcAAtAgAEAAkKaxTwcAAtAgAAAA==.',
Pi='Pinkponyclub:BAABNQAECn8oAAIDAAkKrxvuIADoAgADAAkKrxvuIADoAgAAAA==.Pinkyshock:BAABNQAECn9PAAIIAAkKIh3aCQD9AgAIAAkKIh3aCQD9AgAAAA==.Pista:BAAANQADCgIIAQAAAA==.',
Po='Pog:BAAANQAECgIIAgABNQAECgQICAAJAAAAAA==.Portholes:BAAANQAECgUICgAAAA==.',
Pr='Praystatiøn:BAAANQAECgYIBwAAAA==.',
Ps='Psyop:BAABNQAECn8aAAIFAAkKtRtyHgDvAgAFAAkKtRtyHgDvAgABNQAECgkJOQANAJ8iAA==.',
Pu='Punked:BAAANQADCgYIBgAAAA==.Purplepain:BAAANQAECgcIEAABNQAFFAYIFQAQAFAfAA==.Purplod:BAABNQAECn8gAAMTAAgK/wrySwCCAQATAAgKPgrySwCCAQAMAAUKXAg0jgDHAAAAAA==.',
Py='Pyatpree:BAAANQADCgcIDgAAAA==.',
['Pä']='Päntera:BAAANQADCgMIAwAAAA==.',
Qi='Qing:BAABNQAECn8sAAIhAAgK1hxKCACmAgAhAAgK1hxKCACmAgAAAA==.',
Qy='Qybxboogied:BAAANQAECggICgAAAA==.Qybxboogies:BAAANQAECggIEgAAAA==.Qybxboogyy:BAAANQAECggICAAAAA==.',
Ra='Raensong:BAAANQAECgcICgAAAA==.Rafterman:BAAANQAECgQIBAAAAA==.Rainingarrow:BAAANQABCgIIAwAAAA==.Raisa:BAABNQAECn8sAAMBAAkKEyKjIwDzAgABAAgKzSGjIwDzAgAcAAMK3xoaLwAMAQAAAA==.Rakarum:BAAANQAECgIIAQAAAA==.Rasar:BAABNQAECn8dAAIGAAgKahRSqgAsAgAGAAgKahRSqgAsAgAAAA==.Rathew:BAAANQAECgcIEQAAAA==.Rawnext:BAAANQAECgYIDgABNQAECgkJJAAOAB8dAA==.',
Re='Renaitiaalaa:BAAANQAECgUIAwAAAA==.Renei:BAAANQAECgEIAQABNQAECgcIJAAFAGElAA==.Revenger:BAAANQABCgMIAgAAAA==.Revoker:BAABNQAECn9MAAQEAAkKxxMDUwB1AgAEAAkKIhMDUwB1AgACAAcKUA7ePABmAQAmAAIK6g/bDwB/AAAAAA==.',
Rh='Rhidge:BAAANQADCgYIBgAAAA==.',
Ri='Riddlez:BAABNQAECn8sAAMNAAkKqiNiBACpAwANAAkKqiNiBACpAwAfAAUKsCJ+CADbAQAAAA==.Riott:BAAANQADCgEIAQAAAA==.',
Ro='Romoko:BAAANQADCgIIAgAAAA==.Rorshk:BAAANQAECgcICQAAAA==.Rox:BAAANQAECgYIDQAAAA==.Royal:BAAANQADCgcIDAAAAA==.Royle:BAAANQAECgEIAQAAAA==.Roysham:BAAANQAECgQICAAAAA==.Roywar:BAAANQAECgEIAQAAAA==.',
['Ré']='Réîgn:BAAANQAECgYIEgAAAA==.',
Sa='Sacrus:BAAANQAECgUIDQAAAA==.Samael:BAAANQADCgYIBgAAAA==.Santoss:BAAANQADCgQIBAAAAA==.Sarah:BAABNQAECn8YAAMCAAkKZyERFAC9AgACAAkKZyERFAC9AgAEAAEKcxBMTQFAAAAAAA==.',
Sc='Scalelord:BAAANQADCgYJCwABNQADCggIDAAJAAAAAA==.Scoobear:BAAANQAECgMIBgABNQAECggIGAAPAB8UAA==.',
Se='Seilah:BAAANQADCgMIAwAAAA==.Senisia:BAAANQAECgQIBAAAAA==.Senjougahara:BAACNQAFFH8YAAITAAYK0CGAAgAZAgATAAYK0CGAAgAZAgA1AAQKfzAAAhMACQqHJGAMADADABMACQqHJGAMADADAAAA.Seriyah:BAACNQAFFH8HAAIjAAIKDgnIAwCFAAAjAAIKDgnIAwCFAAA1AAQKfycAAiMACQq2GnsHAOUCACMACQq2GnsHAOUCAAAA.Serph:BAAANQAECgcIDgABNQAECgcIHAAkAOAUAA==.',
Sh='Shabane:BAABNQAECn8jAAIhAAcKNB5/CgBrAgAhAAcKNB5/CgBrAgAAAA==.Shame:BAABNQAECn8xAAIYAAkKeRfFFwCVAgAYAAkKeRfFFwCVAgAAAA==.Shankey:BAAANQADCgYIBgAAAA==.Shasta:BAAANQADCgQIBAAAAA==.Shiminy:BAAANQAECgIIAgAAAA==.Shinobi:BAABNQAECn8dAAIQAAcKBhf0LACtAQAQAAcKBhf0LACtAQAAAA==.Shirls:BAABNQAECn8fAAIDAAgKohtaNQCMAgADAAgKohtaNQCMAgAAAA==.Shivak:BAABNQAECn8xAAIiAAkKYhbABACuAgAiAAkKYhbABACuAgAAAA==.Shivanie:BAAANQAECgcIEAAAAA==.Shock:BAAANQAECgQICQAAAA==.Shredderella:BAABNQAECn8gAAIHAAgKAR7aIwBkAgAHAAgKAR7aIwBkAgAAAA==.Shrug:BAABNQAECn8dAAIbAAgKJhbifAAfAgAbAAgKJhbifAAfAgAAAA==.Shubie:BAAANQABCgIIAgABNQADCgUICwAJAAAAAA==.',
Si='Sicwiddit:BAAANQAECgcIDwAAAA==.',
Sk='Skeeda:BAAANQAECgUICwAAAA==.Skylinex:BAABNQAECn8ZAAIeAAkKBBKtFABAAgAeAAkKBBKtFABAAgAAAA==.Skylinez:BAAANQAECgQIBwAAAA==.Skïttles:BAABNQAECn8cAAQkAAcK4BTjKQDMAQAkAAcK4BTjKQDMAQAWAAEKAQmssgAuAAARAAEKAACcbgAbAAAAAA==.',
Sl='Sleezball:BAABNQAECn8YAAIPAAgKORL6jgACAgAPAAgKORL6jgACAgAAAA==.',
So='Softie:BAAANQAECgEIAQABNQAECgkJIwAbAM8XAA==.Sonictide:BAAANQAECgYIDgAAAA==.Soulscream:BAABNQAECn8kAAINAAkKyB8EFwAbAwANAAkKyB8EFwAbAwAAAA==.',
Sp='Spaghetto:BAABNQAECn8qAAIWAAkKuBiIIADGAgAWAAkKuBiIIADGAgAAAA==.Sprite:BAAANQADCgQJBAAAAA==.',
St='Stacy:BAAANQADCgEIAQAAAA==.Sthompson:BAAANQADCgcIDwAAAA==.Strive:BAAANQADCgIIAgAAAA==.Stumpchuggns:BAAANQAECgIIAgAAAA==.',
Su='Suzel:BAAANQADCggIEgAAAA==.',
Sw='Swiftyninja:BAAANQAECgcIBwABNQAECgkJNAAIAIweAA==.',
Sy='Sydaria:BAAANQABCgIIAgAAAA==.Synder:BAABNQAECn8oAAIiAAkKOAYUDgBkAQAiAAkKOAYUDgBkAQAAAA==.',
Ta='Tainin:BAABNQAECn8kAAIFAAcKYSVGHwDsAgAFAAcKYSVGHwDsAgAAAA==.Takzor:BAAANQABCgIIAgAAAA==.Talogos:BAAANQAECgEIAQAAAA==.Tarynna:BAABNQAECn8kAAIBAAcKGRA3mAClAQABAAcKGRA3mAClAQAAAA==.Tazdingobomb:BAAANQAECgQIBQAAAA==.Tazerface:BAABNQAECn8iAAMSAAgKFg3QDgC7AQASAAgKFg3QDgC7AQAGAAYK7gPZWAH5AAAAAA==.',
Te='Tekin:BAABNQAECn8qAAIDAAgKQhQkWgAIAgADAAgKQhQkWgAIAgAAAA==.Teleprompter:BAAANQAECgQIBwAAAA==.Telrissan:BAABNQAECn8YAAIGAAgKEB5vYwC3AgAGAAgKEB5vYwC3AgAAAA==.Tenkawnor:BAAANQAECgUIBQAAAA==.Tenyroldemon:BAABNQAECn8rAAMXAAgKoCGZBAD3AgAXAAgKoCGZBAD3AgAOAAEK4ghnaAA6AAAAAA==.Tenzingyatso:BAAANQADCgQIBAAAAA==.',
Th='Thald:BAABNQAECn8qAAIhAAgKlRlmCwBSAgAhAAgKlRlmCwBSAgAAAA==.Thaznotmilk:BAAANQADCgYIBwAAAA==.',
Ti='Timzilla:BAAANQAECgUIBQABNQAECgkJJgAMAPYfAA==.Tinytip:BAAANQADCgYIBgAAAA==.Tisakna:BAABNQAECn80AAMGAAkK9COpQwD8AgAGAAgKZCKpQwD8AgASAAMKiiOcGgAbAQAAAA==.',
To='Togon:BAAANQAECggICAAAAA==.Tooezy:BAAANQAECgMIBAAAAA==.Tool:BAAANQAECgUICQAAAA==.Tostitos:BAAANQADCggICwAAAA==.',
Tr='Tralgina:BAABNQAECn8UAAIHAAgK+xR7OQDpAQAHAAgK+xR7OQDpAQAAAA==.Trask:BAABNQAECn8gAAIGAAgKYxWOtwATAgAGAAgKYxWOtwATAgAAAA==.Trishalle:BAAANQADCgQIBAABNQAECgkJHgAWAFUSAA==.Trogdoor:BAAANQAECgIIAgAAAA==.Trokom:BAACNQAFFH8LAAIGAAUKTybICAA1AgAGAAUKTybICAA1AgA1AAQKfy8AAgYACQreJkwCAOoDAAYACQreJkwCAOoDAAE1AAUUBQoLAAYATyYA.Trokopally:BAAANQAECgYIBgABNQAFFAUKCwAGAE8mAA==.',
Tu='Tuggmytotem:BAAANQADCgIIAgAAAA==.',
Uc='Uch:BAABNQAECn8lAAMBAAgKsAzQlACtAQABAAgKsAzQlACtAQAcAAMK6we6UQCIAAAAAA==.',
Uh='Uhh:BAAANQADCgQIBAAAAA==.',
Ul='Ullrian:BAAANQAECggIEAAAAA==.',
Un='Uncletrump:BAAANQADCgYIBgAAAA==.',
Ur='Urbanmech:BAABNQAECn8fAAMQAAgKyh1dGQB0AgAQAAgKyh1dGQB0AgAhAAEKyATXMgAoAAAAAA==.',
Va='Vanderlock:BAAANQADCgYIBgABNQAECgkJNAAkAI4TAA==.Vandermark:BAABNQAECn80AAUkAAkKjhOpHABKAgAkAAkKjhOpHABKAgAjAAQKIBbaHQAqAQAWAAQK1QvEgADIAAARAAIKQBQ1QgCmAAAAAA==.',
Ve='Ventress:BAAANQABCgIIAgAAAA==.',
Vi='Viaos:BAAANQAECgUIDwAAAA==.Victus:BAAANQAECgEIAQAAAA==.Vidrus:BAAANQADCgcIDQAAAA==.Vilkas:BAAANQAFFAEIAgABNQAFFAUICAAYAMYeAA==.Viserion:BAAANQADCgYIEgAAAA==.',
Wa='Waddledoo:BAABNQAECn8gAAIFAAgKkx8CLgCnAgAFAAgKkx8CLgCnAgAAAA==.Warmaku:BAAANQAECgYIEwAAAA==.',
We='Weezybaby:BAAANQAECgQIBAAAAA==.',
Wh='Whïteoak:BAABNQAECn8bAAIkAAkKlRtnEADRAgAkAAkKlRtnEADRAgAAAA==.',
Wi='Wienz:BAAANQADCgMIAwAAAA==.Wishofwar:BAAANQADCgYIBgAAAA==.',
Xa='Xani:BAABNQAECn8dAAIMAAkKxx+fGADmAgAMAAkKxx+fGADmAgAAAA==.Xanyp:BAAANQAECgEJAwABNQAECgkJHQAMAMcfAA==.',
Xe='Xeletath:BAAANQAECgUIBQAAAA==.Xerg:BAAANQADCgUIBQABNQAECggILAAhANYcAA==.',
Xi='Xinaveruk:BAAANQAECggICgAAAA==.',
Xo='Xoro:BAAANQAECgQICQAAAA==.',
Xr='Xrxyz:BAAANQAECggICgAAAA==.',
Xs='Xshamster:BAABNQAECn8yAAMFAAkKVBqCKgC3AgAFAAkKVBqCKgC3AgAKAAEKAACRLQE3AAAAAA==.',
Ye='Yewna:BAAANQAECgIIAwABNQAECgkJNAAFAKskAA==.',
Za='Zaarf:BAAANQADCgYIBgAAAA==.Zachdk:BAAANQADCgUIBgAAAA==.Zachpal:BAAANQADCgcIDQAAAA==.Zachpri:BAAANQAECgEIAQAAAA==.Zanyr:BAAANQADCgMIAQABNQAECgkJHQAMAMcfAA==.Zau:BAABNQAECn8gAAMgAAgKwh2wBgA7AgAgAAcKXiCwBgA7AgABAAQKexNv7QDqAAAAAA==.',
Ze='Zed:BAAANQAECgQIBAABNQAECgkJJAAQABckAA==.',
Zo='Zodiac:BAAANQADCgUIBQABNQAFFAMIBgAGAGMfAA==.Zolja:BAAANQAECgUICwAAAA==.Zoney:BAAANQAECgIIAwAAAA==.Zordlon:BAAANQAECgYIDwAAAA==.',
Zu='Zukem:BAABNQAECn8hAAIEAAgKkCKfMwDPAgAEAAgKkCKfMwDPAgAAAA==.Zulelphie:BAAANQADCgMIBAAAAA==.Zuli:BAAANQAECgQIBQABNQAECgQICgAJAAAAAA==.',
Zy='Zyariah:BAAANQADCgYICwAAAA==.Zyvea:BAABNQAECn8dAAIbAAkKxxqYSgCmAgAbAAkKxxqYSgCmAgAAAA==.',
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
