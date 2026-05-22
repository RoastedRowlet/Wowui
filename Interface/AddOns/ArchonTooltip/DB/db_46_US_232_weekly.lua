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

local lookup = {'Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Priest-Holy','Paladin-Retribution','Paladin-Holy','DemonHunter-Devourer','Druid-Restoration','Druid-Guardian','Mage-Frost','Priest-Shadow','Hunter-BeastMastery','Unknown-Unknown','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','DeathKnight-Unholy','Monk-Brewmaster','Druid-Balance','Monk-Windwalker','Hunter-Marksmanship','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Rogue-Assassination','Warlock-Affliction','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Frost','Druid-Feral','Monk-Mistweaver','Warrior-Arms','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=46,date='2026-05-17',data={Ad='Addiction:BAAALgADCgYJAQAAAA==.',
Ah='Ahmet:BAAALgAECgkJEwABLgAECgkJOAABAP0aAA==.',
Ai='Aiax:BAACLgAFFH8HAAICAAMJRAJfGgCXAAACAAMJRAJfGgCXAAAuAAQKfxcABAMACAlODDQgACwBAAQABgmnDb0xADoBAAMABglkCjQgACwBAAIAAglJB0VGAEAAAAAA.',
Al='Aliancia:BAABLgAECn8pAAIFAAcJfxbbEwBuAQAFAAcJfxbbEwBuAQAAAA==.Almur:BAAALgAECgYJCQAAAA==.Alyda:BAAALgADCggJFAAAAA==.Alydin:BAAALgADCgUJBQAAAA==.',
Am='Amet:BAABLgAECn84AAIBAAkJ/RoNBQBjAgABAAkJ/RoNBQBjAgAAAA==.',
An='Anakinn:BAAALgAECgUJBQAAAA==.Annailuj:BAAALgADCgIJAgAAAA==.Annora:BAABLgAECn8uAAIGAAkJBxspDQBUAgAGAAkJBxspDQBUAgAAAA==.Antherina:BAAALgADCgQJBwAAAA==.Antonious:BAAALgADCgMJAwAAAA==.Antonlavay:BAAALgAECgQJBAAAAA==.',
Ap='Aphyra:BAAALgADCgUJBQAAAA==.Apollyon:BAABLgAECn8mAAMHAAkJxCG1CAD1AgAHAAkJxCG1CAD1AgAIAAIJKhWsfgB/AAAAAA==.',
Ar='Arlechino:BAACLgAFFH8FAAIJAAMJ8AoiRwDOAAAJAAMJ8AoiRwDOAAAuAAQKfxwAAgkACAkXF1lAAPMBAAkACAkXF1lAAPMBAAAA.Arywyn:BAABLgAECn8VAAIKAAYJ2wpBZQDNAAAKAAYJ2wpBZQDNAAAAAA==.',
As='Assclapiuss:BAABLgAECn8uAAIHAAkJiiVaAgBcAwAHAAkJiiVaAgBcAwAAAA==.Asterchades:BAABLgAECn85AAILAAkJoB3DAwCgAgALAAkJoB3DAwCgAgAAAA==.Astlin:BAAALgAECgEJAQAAAA==.Astraeastar:BAAALgADCgUJBQAAAA==.',
At='Athennah:BAAALgAECgcJBwABLgAECggJGQAMAA8cAA==.Atrei:BAAALgADCgIJAgAAAA==.Attikus:BAABLgAECn83AAIMAAkJrAPsgwA7AQAMAAkJrAPsgwA7AQAAAA==.Atuan:BAABLgAECn8VAAINAAYJiRJbLAAsAQANAAYJiRJbLAAsAQAAAA==.',
Au='Auralass:BAABLgAECn8aAAIOAAcJ6xV+QQCWAQAOAAcJ6xV+QQCWAQAAAA==.Aurene:BAAALgAECgkJJwAAAQ==.Autym:BAAALgADCgkJCQAAAA==.',
Av='Avaric:BAAALgAECgEJAQABLgAECgcJDQAPAAAAAA==.Avatard:BAAALgAECgIJAgABLgAFFAMJBQAMAIkEAA==.',
Ax='Axem:BAABLgAECn8gAAIQAAkJsRvfCQCKAgAQAAkJsRvfCQCKAgAAAA==.',
Az='Azlanii:BAAALgADCggJCgAAAA==.Azulathan:BAABLgAECn8ZAAMRAAgJ3RbcBgDVAQARAAgJ3RbcBgDVAQAJAAYJEAm9jgAEAQABLgAECggJNAASAP0TAA==.',
Ba='Bamseyn:BAAALgADCgYJBgAAAA==.Bamsheyn:BAAALgADCgkJCQAAAA==.Baraxor:BAABLgAECn80AAMSAAgJ/RNKMACmAQASAAgJ/RNKMACmAQATAAgJrg/5LQBAAQAAAA==.Barrelaged:BAAALgAECgMJAwAAAA==.',
Be='Beerguy:BAAALgAECgYJDwAAAA==.Behemothe:BAABLgAECn8xAAIUAAkJrSC8AQDjAgAUAAkJrSC8AQDjAgAAAA==.Berníesandrs:BAABLgAECn8sAAIMAAgJeQ9vbQBpAQAMAAgJeQ9vbQBpAQAAAA==.Beryllos:BAAALgAECgMJBQAAAA==.Bevela:BAAALgADCgIJAgAAAA==.',
Bi='Biddies:BAAALgAECgYJBwAAAA==.Bigdmg:BAAALgAECgYJBgAAAA==.Biggusdiscus:BAAALgAECgMJAwAAAA==.Bigimpin:BAAALgADCgcJBwAAAA==.',
Bj='Bjôrn:BAAALgAECgcJDQAAAA==.',
Bl='Bledana:BAAALgAECgQJBQAAAA==.Bleué:BAAALgADCgEJAQABLgAECggJKgAKAGAcAA==.Bloodmourne:BAABLgAECn8qAAIVAAgJpCRNDwC+AgAVAAgJpCRNDwC+AgAAAA==.Bloodytoutii:BAAALgAECgUJBQAAAA==.',
Bo='Borthyr:BAABLgAECn8kAAMEAAkJ4xouCwBtAgAEAAkJjBkuCwBtAgADAAYJ0RyqDgDwAQAAAA==.Bowowner:BAABLgAECn8hAAIOAAgJxR73JQAFAgAOAAgJxR73JQAFAgAAAA==.',
Br='Branchmanagr:BAABLgAECn8iAAILAAkJ6RGUDAC7AQALAAkJ6RGUDAC7AQAAAA==.Brewlee:BAAALgAECgkJEAAAAA==.Bricter:BAAALgADCgkJCAABLgAECgkJLgAMAP4TAA==.Brokenkrayon:BAAALgAECgIJAwAAAA==.Brokkr:BAAALgADCgQJBwAAAA==.Bryce:BAAALgAECgEJAQAAAA==.',
Bu='Bullséye:BAAALgAECgEJAQAAAA==.Busta:BAABLgAECn8fAAIMAAkJZgX9jAArAQAMAAkJZgX9jAArAQAAAA==.',
Bw='Bwicked:BAABLgAECn8bAAIMAAgJCBUuSwDAAQAMAAgJCBUuSwDAAQAAAA==.',
['Bé']='Béck:BAAALgADCgEJAQAAAA==.',
['Bü']='Büg:BAAALgAECgcJDwAAAA==.',
Ca='Caedars:BAAALgADCgEJAQAAAA==.Calzone:BAAALgAECgQJBQAAAA==.Cantpurge:BAAALgADCgIJAgABLgAECgYJEQAPAAAAAA==.Carebears:BAAALgAECgEJAQAAAA==.',
Ce='Celonge:BAAALgADCgQJAwABLgAECgkJJwAIAHMWAA==.',
Ch='Chamelean:BAAALgAECgYJDQABLgAECgkJGAAJAMcTAA==.Chimpnzthat:BAABLgAECn8dAAIWAAcJ5hKyJgBGAQAWAAcJ5hKyJgBGAQAAAA==.Chookicookie:BAABLgAECn81AAMSAAkJrSIyFgBkAgASAAgJPiIyFgBkAgATAAcJ1xfKIQCOAQAAAA==.Chrome:BAABLgAECn85AAMXAAkJ+hxHBwClAgAXAAkJ+hxHBwClAgAKAAgJxx1+HgBLAgAAAA==.Chuckarita:BAABLgAECn8gAAIXAAkJnQonJQBVAQAXAAkJnQonJQBVAQAAAA==.',
Ci='Cindyy:BAABLgAECn8hAAIYAAgJbiGoBwCRAgAYAAgJbiGoBwCRAgABLgAECgkJIgAOAA0eAA==.Civaelia:BAAALgADCgMJAwAAAA==.',
Cl='Clutterbear:BAAALgADCgIJAgAAAA==.',
Co='Cornpuff:BAAALgAECgYJEwAAAA==.Cortiz:BAABLgAECn85AAIOAAkJQxKFLADnAQAOAAkJQxKFLADnAQAAAA==.',
Cr='Crankdog:BAABLgAECn8oAAMOAAkJGSS6AwAqAwAOAAkJGSS6AwAqAwAZAAYJ8g9oSgApAQAAAA==.Creedd:BAABLgAECn8vAAIKAAgJGSC5DgCqAgAKAAgJGSC5DgCqAgAAAA==.Crialta:BAAALgADCgcJFAAAAA==.',
Cu='Cupsandcakes:BAABLgAECn8VAAIaAAYJGAj5BwDiAAAaAAYJGAj5BwDiAAAAAA==.',
Cy='Cynaidia:BAAALgAECgQJBwAAAA==.',
Da='Dacarry:BAAALgAECgIJAgAAAA==.Damessiah:BAABLgAECn8nAAIGAAgJGhQ4FgDgAQAGAAgJGhQ4FgDgAQAAAA==.Dark:BAABLgAECn80AAIbAAkJ2h52EACbAgAbAAkJ2h52EACbAgAAAA==.Darkphyre:BAABLgAECn8VAAIHAAYJXQ0DmQAGAQAHAAYJXQ0DmQAGAQAAAA==.Darkstormn:BAAALgADCggJBwAAAA==.Darthtree:BAAALgADCgEJAQAAAA==.Dawling:BAAALgAECggJCQAAAA==.',
De='Deadmandan:BAABLgAECn8vAAMbAAkJHSW+BAAiAwAbAAkJHSW+BAAiAwAcAAYJISSxBwBMAgAAAA==.Deathomen:BAAALgADCgcJBwAAAA==.Deathtike:BAABLgAECn8xAAIdAAgJDSOHBQCZAgAdAAgJDSOHBQCZAgABLgAECgkJNwARAFQlAA==.Decius:BAABLgAECn8UAAIeAAYJfgfyDwDqAAAeAAYJfgfyDwDqAAAAAA==.Deltairlines:BAAALgAFFAMJAwABLgAFFAQJBAAPAAAAAA==.Deltayaya:BAAALgAFFAQJBAAAAA==.Demagorgin:BAABLgAECn8vAAIHAAkJjRkdIgBCAgAHAAkJjRkdIgBCAgAAAA==.Demcheekz:BAAALgAECgIJAgAAAA==.Demiurge:BAAALgAECgUJBQAAAA==.Demondred:BAAALgAECgYJEAAAAA==.Demonplug:BAAALgADCgEJAQAAAA==.Demonrae:BAAALgAECgIJAgAAAA==.Deqlyn:BAABLgAECn8nAAIHAAkJ0hziFgCEAgAHAAkJ0hziFgCEAgAAAA==.Desmus:BAABLgAECn8dAAIXAAcJnRaRHgCGAQAXAAcJnRaRHgCGAQAAAA==.Deterno:BAAALgADCgUJBQAAAA==.Devige:BAAALgADCgMJBAABLgAFFAQJCwAbAJAfAA==.Devilmaycry:BAAALgADCgEJAQAAAA==.Deáthreaver:BAABLgAECn8cAAIHAAgJAQ7+ZQBnAQAHAAgJAQ7+ZQBnAQAAAA==.',
Di='Diglett:BAAALgADCgYJAQAAAA==.Dimsum:BAAALgAECgUJBgAAAA==.Diqtator:BAAALgADCgcJBwAAAA==.Dismal:BAABLgAECn8eAAIIAAkJJxK+GQD2AQAIAAkJJxK+GQD2AQAAAA==.Ditar:BAAALgAECgEJAgABLgAECgYJCQAPAAAAAA==.',
Dk='Dk:BAAALgADCgIJAgABLgAFFAMJCQAOABkkAA==.',
Do='Domwarlock:BAABLgAFFH8FAAMfAAMJjQzDEgBMAAAbAAIJ+AtLeQCPAAAfAAEJtQ3DEgBMAAAAAA==.Doogang:BAAALgADCgEJAQAAAA==.Doomdooms:BAAALgADCgEJAQAAAA==.Dots:BAAALgADCggJDgAAAA==.',
Dr='Dradin:BAAALgADCgMJAwAAAA==.Dragondznutz:BAAALgAECgYJBwABLgAECgkJLgAHAIolAA==.Dronin:BAABLgAECn8iAAMZAAgJ/haRCwBoAQAZAAcJZRaRCwBoAQAOAAMJNBfHqACQAAAAAA==.Drpatan:BAABLgAECn8ZAAIgAAcJJgXLSgDFAAAgAAcJJgXLSgDFAAAAAA==.Druni:BAABLgAECn8VAAIBAAYJowckJgCeAAABAAYJowckJgCeAAAAAA==.Dryan:BAAALgADCgEJAQAAAA==.',
Ec='Echowalker:BAABLgAECn8YAAIgAAcJWBjuEwCcAQAgAAcJWBjuEwCcAQAAAA==.',
Ee='Eecho:BAAALgADCgEJAQAAAA==.',
Ei='Eisenthorne:BAAALgADCgEJAgAAAA==.',
El='Eldruida:BAAALgADCgYJDAAAAA==.Elguezo:BAAALgAECgYJDAAAAA==.Elysyn:BAAALgADCgMJAwAAAA==.',
Em='Emaelia:BAAALgAECgQJBAAAAA==.Emokillaz:BAABLgAECn8WAAIgAAcJ2hitIwCgAQAgAAcJ2hitIwCgAQAAAA==.',
Ep='Epictaxes:BAAALgADCgEJAQAAAA==.Epimetheuz:BAAALgADCgYJAwABLgAECgUJBAAPAAAAAA==.Epsi:BAAALgADCgQJBAAAAA==.Epsilón:BAAALgAECgYJEQAAAA==.',
Et='Eternalpeace:BAAALgAECgEJAgAAAA==.',
Ev='Evelana:BAAALgADCgQJBwAAAA==.',
Ex='Exaduss:BAABLgAECn8VAAMcAAgJUiH+CAAxAgAcAAgJUiH+CAAxAgAbAAQJHB5pZgBBAQAAAA==.',
Ez='Ezora:BAAALgAECgYJBgAAAA==.',
Fa='Famulimus:BAAALgAECgUJBQABLgAECggJEAAPAAAAAA==.Fastrolling:BAAALgADCgQJCgAAAA==.Faxon:BAABLgAECn8YAAIOAAgJLhjGNgC9AQAOAAgJLhjGNgC9AQAAAA==.Faylan:BAABLgAECn8VAAIOAAYJ/A0AcgARAQAOAAYJ/A0AcgARAQAAAA==.',
Fe='Feronnia:BAAALgAECgMJAwAAAA==.',
Fi='Fibot:BAABLgAECn82AAIUAAkJ/RwOAwCdAgAUAAkJ/RwOAwCdAgAAAA==.Fingon:BAAALgAECgcJEgAAAA==.',
Fl='Flogor:BAAALgAECgcJBgABLgAECgkJFgAMAMQUAA==.Florasol:BAAALgADCgIJAgAAAA==.',
Fo='Foxling:BAEALgAECgIJAgAAAA==.',
Fr='Fraeyah:BAAALgAECgYJBgAAAA==.Frahaad:BAAALgADCgQJBAAAAA==.Freebunz:BAACLgAFFH8JAAIMAAMJzg4eWgD0AAAMAAMJzg4eWgD0AAAuAAQKfxYAAgwACQkaF2ZUADsCAAwACQkaF2ZUADsCAAAA.',
Fu='Fulgora:BAAALgAECgcJDQAAAA==.Fullmoon:BAAALgAECgcJBwAAAA==.Furicor:BAAALgADCgEJAQAAAA==.',
Ga='Gahydra:BAAALgADCgkJEwAAAA==.Galvanize:BAACLgAFFH8NAAIMAAQJDQtcRgAvAQAMAAQJDQtcRgAvAQAuAAQKfzQAAgwACQlcGpInAEQCAAwACQlcGpInAEQCAAAA.Gasaraki:BAAALgAECgEJAQAAAA==.Gastdhunter:BAAALgAECgEJAQAAAA==.Gastrophos:BAAALgAECgEJAQAAAA==.',
Gh='Ghomertin:BAAALgADCggJCgAAAA==.',
Gi='Gimtar:BAAALgAECgYJCQAAAA==.Ginjockey:BAAALgADCgUJBQABLgAECgYJEQAPAAAAAA==.Gipsydanger:BAABLgAECn88AAIhAAkJ3RyJBwC/AgAhAAkJ3RyJBwC/AgAAAA==.Girllygirl:BAAALgAECgYJDAAAAA==.Givr:BAAALgADCgEJAQAAAA==.',
Gl='Gladiatrix:BAAALgAECgMJBAAAAA==.Glaurang:BAAALgAECgQJCwAAAA==.Glofor:BAAALgAECgcJCgABLgAECgkJFgAMAMQUAA==.',
Gn='Gnarp:BAAALgADCgEJAQABLgAECggJGAASAMcWAA==.Gnomeregrets:BAAALgAECgUJBQAAAA==.Gnomestone:BAAALgAECgcJBwAAAA==.',
Go='Goldencorpse:BAAALgAECgUJBQAAAA==.Goldenspoon:BAAALgADCgEJAQABLgAECggJGQAbALkkAA==.Gorlokk:BAEALgADCgMJAwABLgADCgkJHwAPAAAAAA==.',
Gr='Grakonys:BAABLgAECn8qAAMEAAkJ/A8OHACxAQAEAAkJ/A8OHACxAQADAAcJ4Qc7HQBFAQAAAA==.Granger:BAAALgAECgIJAgABLgAECgIJBAAPAAAAAA==.Greed:BAABLgAECn80AAIYAAkJHhtMCACEAgAYAAkJHhtMCACEAgAAAA==.Greensun:BAAALgADCgEJAQAAAA==.Grendol:BAAALgAECgMJAwAAAA==.Grimmbot:BAAALgAECgMJBQAAAA==.Grimmvelt:BAAALgAECgQJBAAAAA==.Grunnck:BAAALgADCgkJHgAAAA==.',
Gu='Guayusa:BAAALgAECggJEwAAAA==.Gunned:BAAALgADCgEJAQAAAA==.',
Gw='Gwendolin:BAAALgAECgUJBQAAAA==.Gwenfrewi:BAAALgADCgEJAQABLgADCgEJAQAPAAAAAA==.',
Ha='Hacheron:BAAALgADCgIJAgABLgAFFAQJCAARAG0QAA==.Hallows:BAAALgAECgQJBQAAAA==.Harnix:BAABLgAECn8YAAIHAAcJGA1xgAAxAQAHAAcJGA1xgAAxAQAAAA==.Hawtbooty:BAABLgAECn8lAAIGAAkJ+xkhHQD1AQAGAAkJ+xkhHQD1AQAAAA==.',
He='Heartsbane:BAAALgAECgEJAQAAAA==.Helixrage:BAABLgAECn8VAAIFAAgJkga5HwDzAAAFAAgJkga5HwDzAAAAAA==.Hellreines:BAABLgAECn8bAAIiAAcJMyDvBQDmAQAiAAcJMyDvBQDmAQAAAA==.Herpderplol:BAABLgAECn8ZAAIjAAgJNRDYDgB1AQAjAAgJNRDYDgB1AQAAAA==.',
Hi='Hildi:BAABLgAECn8dAAMkAAcJMALfVwCCAAAkAAcJMALfVwCCAAAYAAEJyAEnjAAfAAAAAA==.Him:BAACLgAFFH8FAAIQAAIJpxfYKQClAAAQAAIJpxfYKQClAAAuAAQKfyEAAhAACAmoJGoIAKECABAACAmoJGoIAKECAAAA.',
Ho='Holy:BAACLgAFFH8FAAIhAAIJDREdKACPAAAhAAIJDREdKACPAAAuAAQKfzMAAyEACAmlIUYFAPoCACEACAmlIUYFAPoCAAYAAQmDHCNTAEwAAAAA.Holyscales:BAAALgAECgEJAQAAAA==.Hoots:BAAALgAECgEJAQAAAA==.',
Hu='Hucklebury:BAAALgADCgYJDQAAAA==.Hulkcrush:BAAALgADCgUJEQAAAA==.Humânity:BAAALgADCgYJBgAAAA==.',
['Hø']='Høåx:BAAALgADCggJCAABLgAECgQJBAAPAAAAAA==.',
Il='Illbloodarch:BAABLgAECn8vAAIlAAkJWg01EQCYAQAlAAkJWg01EQCYAQAAAA==.Illvicious:BAAALgAECgMJBgAAAA==.',
In='Incredibread:BAAALgAECgUJCAAAAA==.Indub:BAAALgAECgUJBwAAAA==.',
Ir='Ironfistmogu:BAAALgADCgkJCQAAAA==.',
Is='Ishura:BAABLgAECn8cAAIIAAcJgAufNAA9AQAIAAcJgAufNAA9AQAAAA==.',
It='Itslevi:BAAALgAECgcJEQAAAA==.',
Iv='Ivvy:BAABLgAECn8UAAIXAAcJoQdgOADnAAAXAAcJoQdgOADnAAAAAA==.',
Iz='Izanami:BAABLgAECn8cAAIgAAYJjBrlFQCFAQAgAAYJjBrlFQCFAQAAAA==.',
Ja='Jadinkalage:BAAALgAECgQJBAAAAA==.Jaewreth:BAAALgAECgIJAgAAAA==.Janntro:BAABLgAECn8ZAAMgAAkJLhpGCgAxAgAgAAkJthlGCgAxAgARAAIJ4hjFGACWAAAAAA==.Jantra:BAAALgAECgEJAgABLgAECgkJGQAgAC4aAA==.Jantro:BAABLgAECn8UAAILAAgJsB41BwAvAgALAAgJsB41BwAvAgABLgAECgkJGQAgAC4aAA==.Janttro:BAAALgAECgIJAwABLgAECgkJGQAgAC4aAA==.Jaquavious:BAAALgADCgcJBwAAAA==.',
Je='Jeebz:BAABLgAECn8oAAMSAAkJshPxKQDIAQASAAkJshPxKQDIAQATAAMJxQqUbACRAAAAAA==.Jelmarr:BAAALgAECgcJDAAAAA==.Jemmâ:BAAALgAECggJEQAAAA==.Jerauld:BAABLgAECn8cAAIjAAcJWw6BEwAxAQAjAAcJWw6BEwAxAQAAAA==.Jezrra:BAAALgAECggJDwAAAA==.',
Jh='Jhuloot:BAAALgADCgYJCQAAAA==.',
Ji='Jiddles:BAAALgADCgMJAwABLgAECggJFAASAKsdAA==.',
Jo='Johnnyzyns:BAABLgAECn8qAAMVAAgJoRxsKwAXAgAVAAgJoRxsKwAXAgAdAAEJthh7QgBAAAAAAA==.Jokhasta:BAABLgAECn8ZAAIUAAgJvhY/CwAYAgAUAAgJvhY/CwAYAgAAAA==.Joshc:BAABLgAECn8qAAILAAgJggwhHAAAAQALAAgJggwhHAAAAQAAAA==.',
Jp='Jpmeister:BAAALgADCgkJDQAAAA==.',
Ju='Judgejudee:BAAALgADCgcJEwAAAA==.',
['Já']='Ják:BAABLgAECn8bAAQBAAgJzBMPGwA2AQABAAcJJhEPGwA2AQAIAAMJvwuuZgBTAAAHAAEJpwMyWwEmAAAAAA==.',
Ka='Kaaris:BAAALgAECgcJEQAAAA==.Kaetora:BAAALgADCgkJCQAAAA==.Kaiarie:BAABLgAECn8aAAIfAAcJ4QhwDgAYAQAfAAcJ4QhwDgAYAQAAAA==.Kainraziel:BAABLgAECn8YAAIJAAkJxxOsOAClAQAJAAkJxxOsOAClAQAAAA==.Kairos:BAABLgAECn81AAIMAAkJKg3STQC4AQAMAAkJKg3STQC4AQAAAA==.Kalasta:BAAALgADCgIJAgAAAA==.Kanzak:BAAALgADCgcJCgAAAA==.Karem:BAAALgAECgEJAQAAAA==.Karkea:BAAALgAECgEJAwAAAA==.Kayper:BAAALgAECgcJAgAAAA==.',
Ke='Kebin:BAABLgAECn8pAAIFAAgJJhnqDQDHAQAFAAgJJhnqDQDHAQAAAA==.Kekkoken:BAAALgAECgEJAQAAAA==.Kelfhammer:BAAALgADCgQJBAAAAA==.Kenkenif:BAAALgAECgQJBAAAAA==.',
Kh='Khlorox:BAAALgADCgYJBgAAAA==.Khronin:BAAALgADCgIJAgAAAA==.',
Ki='Killmonger:BAAALgAECgYJCwAAAA==.Kimsambo:BAAALgAECgQJBAAAAA==.',
Kl='Klöwÿ:BAAALgAECgEJAQAAAA==.',
Ko='Korax:BAAALgAECgUJBQAAAA==.Korgia:BAAALgAECgQJBAAAAA==.Kortharion:BAABLgAECn8qAAICAAgJRiKcAgALAwACAAgJRiKcAgALAwAAAA==.Korzillian:BAAALgAECgEJAQAAAA==.Kos:BAABLgAECn8jAAINAAkJsyF9AwABAwANAAkJsyF9AwABAwAAAA==.',
Kr='Kreyali:BAAALgAECgEJAQAAAA==.Krixis:BAAALgADCgEJAgAAAA==.',
Ku='Kujiera:BAAALgAECgcJEwAAAA==.Kuntar:BAAALgAECgcJCwAAAA==.Kurgan:BAAALgADCggJCAAAAA==.Kurkoh:BAAALgAECgIJBAAAAA==.Kurrent:BAABLgAECn8UAAISAAgJqx2xFwBEAgASAAgJqx2xFwBEAgAAAA==.',
['Kÿ']='Kÿtten:BAABLgAECn8kAAIBAAkJwgqjEgBRAQABAAkJwgqjEgBRAQAAAA==.',
La='Lad:BAAALgAFFAEJAQABLgAFFAIJBQAJAOQJAA==.Laiyth:BAABLgAECn8bAAIbAAkJfxLfKwD3AQAbAAkJfxLfKwD3AQAAAA==.Lanfearz:BAAALgADCgEJAQAAAA==.Larryfish:BAABLgAECn8ZAAIVAAgJGR7gKgAaAgAVAAgJGR7gKgAaAgAAAA==.Laslock:BAAALgADCgEJAQAAAA==.Lavahitman:BAAALgAECgMJBAAAAA==.Lavos:BAABLgAECn8nAAIcAAkJlg1jCQBqAQAcAAkJlg1jCQBqAQAAAA==.',
Le='Levitikus:BAAALgAECgIJBQAAAA==.Levìtikus:BAAALgAECgEJAgAAAA==.',
Li='Lideysse:BAAALgADCgUJBQAAAA==.Lighteyes:BAAALgADCgEJAQAAAA==.Lildragon:BAAALgAECgYJBgAAAA==.Lisster:BAABLgAECn8qAAMOAAgJwh9WGgBFAgAOAAgJwh9WGgBFAgAZAAEJkAG2mAAeAAAAAA==.Littledoty:BAAALgAECgEJAQAAAA==.Liyra:BAABLgAECn8dAAMIAAkJNhuwIAAWAgAIAAkJNhuwIAAWAgABAAEJBBULQQA5AAAAAA==.Lizcandor:BAAALgAECgMJCgAAAA==.',
Lo='Loafe:BAABLgAECn8oAAIHAAgJlg0jZQC2AQAHAAgJlg0jZQC2AQAAAA==.Lokni:BAAALgAECgYJEQAAAA==.Loriann:BAAALgAECgEJAQAAAA==.Loumin:BAAALgADCgkJCQAAAA==.',
Lu='Ludacritz:BAAALgAECggJDgAAAA==.Lunaignis:BAAALgADCgYJBgAAAA==.Lunasera:BAAALgADCgcJBwAAAA==.Luthais:BAABLgAECn8VAAIBAAYJHw1QIADHAAABAAYJHw1QIADHAAAAAA==.Luxury:BAABLgAECn8jAAIFAAgJTwImJQDJAAAFAAgJTwImJQDJAAAAAA==.',
Ma='Mahroq:BAABLgAECn8hAAMGAAgJnxnGFQDlAQAGAAgJnxnGFQDlAQAhAAEJkQIQXgAmAAAAAA==.Mako:BAACLgAFFH8IAAICAAMJig36FwC8AAACAAMJig36FwC8AAAuAAQKfxwAAgIACAn7IEwDAOMCAAIACAn7IEwDAOMCAAAA.Malarkeclark:BAAALgADCgkJCQAAAA==.Malevian:BAABLgAECn8nAAMDAAgJDwyeCgA3AQADAAgJygieCgA3AQAEAAcJtgq8NQAjAQAAAA==.Malfuridan:BAAALgAECgMJAgAAAA==.Malocki:BAAALgADCgQJCgAAAA==.Maples:BAABLgAECn8nAAMkAAkJXQp1KgBfAQAkAAkJXQp1KgBfAQAYAAMJ3gHpjQAUAAAAAA==.Mariasha:BAAALgAECgUJCQAAAA==.Marichika:BAAALgADCgYJCgAAAA==.Maryjaine:BAAALgADCgEJAQAAAA==.Mattdeamon:BAAALgADCgUJBwABLgAFFAQJDQAMAA0LAA==.Mazzikin:BAABLgAECn8jAAIJAAgJXB4fGABNAgAJAAgJXB4fGABNAgAAAA==.',
Mc='Mcdodgy:BAAALgADCgEJAQAAAA==.',
Me='Megaterium:BAABLgAECn8iAAMGAAcJWRgAGwCzAQAGAAcJWRgAGwCzAQANAAMJ3wTGUwB2AAAAAA==.Menethil:BAABLgAECn8bAAIIAAYJRyTiFwAIAgAIAAYJRyTiFwAIAgAAAA==.Metheuz:BAAALgAECgUJBAAAAA==.Mexican:BAABLgAECn8qAAIMAAgJVxMCWwCVAQAMAAgJVxMCWwCVAQAAAA==.',
Mi='Midnightlock:BAAALgAECgYJDQAAAA==.Midnyght:BAAALgAECgMJBQAAAA==.Mishgrail:BAABLgAECn8nAAIWAAkJTh+BBADSAgAWAAkJTh+BBADSAgAAAA==.Missmisery:BAAALgAECgcJEwAAAA==.Mithdraug:BAABLgAECn8UAAMXAAYJsQ0INwDuAAAXAAYJsQ0INwDuAAAKAAMJ/QTrsABjAAAAAA==.Mitzi:BAACLgAFFH8VAAMVAAcJghbAFACnAQAVAAYJghbAFACnAQAdAAEJAACyPwAAAAAuAAQKfyQAAhUACQlwI8cZAHMCABUACQlwI8cZAHMCAAAA.',
Mo='Modrem:BAAALgADCgkJCQAAAA==.Mokhan:BAAALgADCgkJCQAAAA==.Molsan:BAAALgAECgQJBAAAAA==.Monache:BAABLgAECn8UAAIQAAYJ/QlcRQDsAAAQAAYJ/QlcRQDsAAAAAA==.Mongalf:BAAALgADCgQJBAAAAA==.Montrois:BAAALgAECgQJBAAAAA==.Moopally:BAAALgAECgQJCAAAAA==.',
My='Mythrilblade:BAAALgAECgYJBgAAAA==.',
['Mô']='Môônmôôn:BAAALgADCgYJBgAAAA==.',
Ne='Neletheus:BAABLgAECn8WAAIbAAcJihBDYgBLAQAbAAcJihBDYgBLAQAAAA==.Nephbrew:BAAALgADCgEJAQAAAA==.Nephren:BAAALgADCgYJBgAAAA==.Nephwren:BAAALgADCgUJBQAAAA==.',
Ni='Nightparade:BAABLgAECn8WAAIVAAYJZh/aTwCbAQAVAAYJZh/aTwCbAQAAAA==.Nirvanik:BAAALgAECgEJAQAAAA==.Nishgrail:BAAALgADCgYJBAABLgAECgkJJwAWAE4fAA==.',
Nu='Nukusmaximus:BAABLgAECn8YAAIMAAcJ9wd1mQAWAQAMAAcJ9wd1mQAWAQAAAA==.',
Ny='Nyeneave:BAAALgAECgIJAgAAAA==.Nyiah:BAABLgAECn8YAAIKAAgJyhY3KADVAQAKAAgJyhY3KADVAQAAAA==.',
['Nä']='Närgazeth:BAAALgADCgMJAwAAAA==.',
Og='Ogdoadtl:BAAALgADCgkJKAAAAA==.',
Oh='Ohello:BAAALgADCgUJBQAAAA==.',
Ol='Oldbull:BAAALgADCgEJAQAAAA==.',
On='Onex:BAAALgAECgYJCQAAAA==.',
Or='Organicmeat:BAAALgAECggJCQAAAA==.Orgrím:BAAALgADCgMJAwAAAA==.Ori:BAAALgAECgQJBAAAAA==.',
Pa='Palii:BAAALgAECgQJBAAAAA==.Partywizard:BAAALgAECgMJAwAAAA==.',
Pe='Persefini:BAAALgAECgYJEAAAAA==.Persephoneia:BAAALgADCgcJDQAAAA==.Petrokull:BAAALgAECgMJAwAAAA==.',
Ph='Pheeguh:BAAALgADCgkJEAAAAA==.Pheylan:BAAALgAECgUJCwAAAA==.Philidox:BAAALgAECgYJCgABLgAECggJGwABAMwTAA==.Phood:BAAALgADCgcJBwAAAA==.',
Pi='Pikxs:BAAALgAECgMJAgAAAA==.Pitchou:BAAALgAECgQJBQAAAA==.',
Pl='Plugugly:BAAALgAECgIJAgAAAA==.',
Po='Poenin:BAAALgAECgEJAQAAAA==.Pokeball:BAAALgAECgYJDAAAAA==.Polinemarois:BAAALgADCggJBwAAAA==.Porkque:BAABLgAECn8fAAIOAAkJHQ2BOwCrAQAOAAkJHQ2BOwCrAQAAAA==.Potatobear:BAABLgAECn8tAAQOAAkJKiODBQALAwAOAAgJ1yWDBQALAwAmAAkJYBqzCABkAgAZAAYJXyPxGQBbAgAAAA==.',
Pr='Prifduwies:BAAALgADCgcJAQAAAA==.Professorson:BAAALgAECgMJBAAAAA==.',
Qi='Qiursi:BAAALgAECgUJBQAAAA==.',
Qu='Quicktime:BAABLgAECn8zAAIJAAkJMxs9EgB3AgAJAAkJMxs9EgB3AgAAAA==.',
Ra='Ragedh:BAAALgAECgcJCgAAAA==.Ragnarlothbr:BAAALgADCgQJBAAAAA==.Ragnoir:BAAALgAECggJEAAAAA==.Ranillan:BAAALgAECgYJBgAAAA==.Rased:BAAALgADCgEJAQAAAA==.Rashish:BAAALgADCgIJAgAAAA==.Ravies:BAAALgAECgcJCwAAAA==.Rawdøg:BAAALgADCgEJAQAAAA==.Rayaz:BAAALgAECgUJCwABLgAECggJEAAPAAAAAA==.',
Re='Reeses:BAEALgADCgkJHwAAAA==.Reinhearts:BAAALgAFFAEJAQAAAA==.Religgar:BAABLgAECn8lAAIVAAgJ2xeLNQDwAQAVAAgJ2xeLNQDwAQAAAA==.Rethart:BAAALgADCgcJBwAAAA==.',
Rh='Rhilik:BAAALgADCgQJBAAAAA==.',
Ri='Ricter:BAABLgAECn8uAAIMAAkJ/hNARADWAQAMAAkJ/hNARADWAQAAAA==.Rictor:BAAALgAECgIJAwAAAA==.',
Ro='Roglof:BAABLgAECn8WAAIMAAcJxBTkagBuAQAMAAcJxBTkagBuAQAAAA==.Rokkoks:BAAALgADCggJEAAAAA==.Rowlah:BAAALgADCggJCgAAAA==.Roxyfoxy:BAAALgAECgYJCgABLgAECgcJBwAPAAAAAA==.Rozy:BAABLgAECn8vAAIIAAkJGBtuEgB/AgAIAAkJGBtuEgB/AgAAAA==.',
Ru='Ruffs:BAABLgAECn8XAAMJAAkJIB3/EQB5AgAJAAkJIB3/EQB5AgARAAEJYhD3JQA1AAAAAA==.Ruiizu:BAABLgAECn8qAAIHAAgJHyTyDwC1AgAHAAgJHyTyDwC1AgAAAA==.Rulnathil:BAAALgADCgMJBgAAAA==.Rushuna:BAABLgAECn80AAIhAAkJhxp6DABdAgAhAAkJhxp6DABdAgAAAA==.',
Sa='Saberjaw:BAABLgAECn8XAAMmAAYJrBU3FACCAQAmAAYJkRQ3FACCAQAOAAIJvwunzwBIAAAAAA==.Sairicck:BAABLgAECn8lAAIOAAgJHh/jHgApAgAOAAgJHh/jHgApAgAAAA==.Samaal:BAAALgADCgUJBQABLgAECgkJGQAgAC4aAA==.Samial:BAAALgADCgYJDAABLgAECgkJGQAgAC4aAA==.Sanguinor:BAAALgADCgYJFAAAAA==.Santamorte:BAAALgADCggJCgAAAA==.Sashay:BAAALgADCgYJCwAAAA==.Satoru:BAAALgAECgEJAgAAAA==.Satsuki:BAAALgADCgEJAQAAAA==.',
Sc='Scuba:BAAALgAECgUJCAAAAA==.',
Se='Selesé:BAAALgAECgEJAQABLgAECggJEQAPAAAAAA==.Selinora:BAAALgAECgkJDgAAAA==.Serhalatath:BAAALgAECgYJCQAAAA==.',
Sh='Shadowsbane:BAAALgADCgEJAQAAAA==.Shaguar:BAABLgAECn8jAAMHAAgJaiG+FgCFAgAHAAgJaiG+FgCFAgAIAAcJPhCGXAALAQAAAA==.Shamhawk:BAAALgADCgMJBgAAAA==.Shaolinsnake:BAAALgAECgYJDwAAAA==.Shiiva:BAAALgADCgMJAwAAAA==.Shizukahime:BAAALgAECgMJAwAAAA==.Shizzite:BAAALgADCgIJAgAAAA==.',
Si='Sicken:BAAALgADCgIJAgAAAA==.Sigiloc:BAAALgADCgcJBwAAAA==.Silverchair:BAAALgADCgQJBAAAAA==.Singe:BAACLgAFFH8FAAIMAAMJiQRaZgDTAAAMAAMJiQRaZgDTAAAuAAQKfyIAAgwACAm3EFxpAAMCAAwACAm3EFxpAAMCAAAA.Sinzala:BAABLgAECn8iAAIMAAkJVR8sEQDEAgAMAAkJVR8sEQDEAgAAAA==.',
Sk='Skeetsurfin:BAAALgAECgMJAwAAAA==.Skelly:BAAALgADCgYJCwAAAA==.Skyman:BAAALgADCgkJEwAAAA==.',
Sm='Smallblackdk:BAAALgAECgMJBgAAAA==.Smaugdor:BAAALgADCgcJBgAAAA==.',
Sn='Snorp:BAAALgAECgQJBAAAAA==.',
So='Solai:BAAALgAECgEJAQAAAA==.Solsti:BAABLgAECn8nAAIIAAkJcxbCFgASAgAIAAkJcxbCFgASAgAAAA==.',
Sp='Spears:BAAALgAECgYJDQAAAA==.Spoondot:BAABLgAECn8ZAAMbAAgJuSQqDgCvAgAbAAgJbSMqDgCvAgAfAAUJAyDeBwDRAQAAAA==.Spoonknight:BAABLgAECn8XAAMVAAkJLx1aGAB8AgAVAAgJxB1aGAB8AgAiAAgJuBrQBAAVAgABLgAECggJGQAbALkkAA==.',
Sq='Squidge:BAAALgAECgIJAgAAAA==.',
St='Staceyrella:BAAALgADCgMJAwAAAA==.Stainpngolin:BAABLgAECn8dAAILAAcJjx6XCQD1AQALAAcJjx6XCQD1AQAAAA==.Stillhorn:BAABLgAECn8XAAMJAAgJ0BVpNAC2AQAJAAgJ0BVpNAC2AQAgAAIJ/A/bTQAzAAAAAA==.Stinjeras:BAABLgAECn8qAAIbAAgJFyI5FAB9AgAbAAgJFyI5FAB9AgAAAA==.Stinkyjo:BAABLgAECn8qAAIKAAgJ/hniFwBLAgAKAAgJ/hniFwBLAgAAAA==.Stokelys:BAAALgADCgMJAwAAAA==.Stormfeather:BAAALgAECgEJAQAAAA==.Strikerv:BAABLgAECn8iAAIOAAkJhh6AEACMAgAOAAkJhh6AEACMAgAAAA==.',
Su='Sunadoria:BAAALgAECgUJEwAAAA==.Sunlite:BAAALgAECgEJAQAAAA==.Sunrae:BAABLgAECn8ZAAQhAAcJWBerGADBAQAhAAcJThWrGADBAQAGAAMJShQXXQC+AAANAAUJcwn/SwCMAAAAAA==.Sushi:BAABLgAECn8YAAIWAAgJfhG+HgB+AQAWAAgJfhG+HgB+AQAAAA==.',
Sv='Sven:BAAALgAECgUJCQAAAA==.',
Sy='Sylinsor:BAAALgADCgEJAQAAAA==.Symor:BAAALgAECgMJBQAAAA==.',
['Sö']='Söap:BAAALgAECgUJBQAAAA==.',
Ta='Taggert:BAAALgAECgEJAQAAAA==.Tahl:BAABLgAECn8oAAIGAAcJwhFGIgB2AQAGAAcJwhFGIgB2AQAAAA==.Tamanovitch:BAAALgAECgEJAQAAAA==.Tamashii:BAAALgAECgQJBAABLgAFFAMJCAACAIoNAA==.Tangriah:BAAALgADCgEJAQAAAA==.Taproot:BAAALgADCgEJAQABLgAFFAQJDQAMAA0LAA==.Taryen:BAAALgAECgEJAQABLgAECgcJCgAPAAAAAA==.Tavie:BAABLgAFFH8QAAIMAAQJ8xfKMgBSAQAMAAQJ8xfKMgBSAQAAAA==.',
Te='Teddy:BAAALgADCgYJBgAAAA==.Tedo:BAAALgADCgcJDQABLgAFFAQJDgAIABgaAA==.Teikkas:BAAALgAECgYJCgAAAA==.Telaari:BAAALgAECgIJAgAAAA==.',
Th='Thalenia:BAABLgAECn8nAAMZAAgJVglTFQDWAAAOAAYJFAwsYQBEAQAZAAgJYQZTFQDWAAAAAA==.Thallenia:BAAALgADCgEJAQAAAA==.Thalron:BAAALgADCgEJAgAAAA==.Thekingdom:BAABLgAECn8eAAIMAAgJVh1fRQBnAgAMAAgJVh1fRQBnAgAAAA==.Thriller:BAAALgAECgUJCgABLgAFFAQJDgAIABgaAA==.',
Ti='Tikeidari:BAABLgAECn83AAIRAAkJVCVCAABaAwARAAkJVCVCAABaAwAAAA==.Tiltedtroll:BAABLgAECn8lAAITAAgJ2xHPKABfAQATAAgJ2xHPKABfAQAAAA==.Timedemon:BAABLgAECn8mAAIJAAkJcRuwHAAvAgAJAAkJcRuwHAAvAgAAAA==.Tinuveuil:BAAALgADCgYJBgAAAA==.',
To='Tonjuras:BAAALgAECggJEwAAAA==.Toona:BAACLgAFFH8FAAIJAAIJ5Ak6YgB7AAAJAAIJ5Ak6YgB7AAAuAAQKfxwAAgkACQn7GgYcAKoCAAkACQn7GgYcAKoCAAAA.Torogrande:BAAALgADCgkJKgAAAA==.Touchmyting:BAAALgAECgEJAgAAAA==.Toutii:BAAALgAECgUJBgAAAA==.',
Tr='Trappydh:BAABLgAFFH8IAAIRAAQJbRDtAwDsAAARAAQJbRDtAwDsAAAAAA==.Trappydk:BAABLgAECn8WAAIdAAgJhRoZDgDcAQAdAAgJhRoZDgDcAQABLgAFFAQJCAARAG0QAA==.Trintran:BAAALgADCgIJAgAAAA==.',
Tu='Tulshira:BAAALgADCgYJBgAAAA==.',
Tw='Twocents:BAABLgAECn8sAAMbAAgJsSStCwAdAwAbAAgJsSStCwAdAwAfAAEJAADgIQBqAAAAAA==.',
Ty='Tyraxus:BAAALgADCgkJCAAAAA==.Tyronne:BAAALgAECgcJBwAAAA==.',
Ul='Ultraball:BAAALgAECggJDwAAAA==.',
Un='Unagi:BAABLgAECn8gAAImAAYJbw9AJQA1AQAmAAYJbw9AJQA1AQAAAA==.Unkelb:BAAALgADCgYJBgAAAA==.',
Va='Vaenessa:BAABLgAECn8YAAIMAAgJOAhQfABKAQAMAAgJOAhQfABKAQAAAA==.Vaesir:BAAALgADCgcJDQAAAA==.Varleara:BAABLgAECn8gAAMJAAgJziFEEwDmAgAJAAgJziFEEwDmAgARAAEJKQeHLQAqAAAAAA==.',
Ve='Venenn:BAAALgADCgEJAgAAAA==.Venev:BAAALgAECgUJBQAAAA==.Ventana:BAABLgAECn8lAAIUAAgJeB/fBABWAgAUAAgJeB/fBABWAgAAAA==.Verdilac:BAABLgAECn8qAAIHAAgJHRwLTQD7AQAHAAgJHRwLTQD7AQABLgAFFAIJBgAjAKEfAA==.',
Vi='Vinceglortho:BAAALgAECgMJBAAAAA==.Vindicator:BAABLgAECn8XAAIHAAgJpBtKKwAVAgAHAAgJpBtKKwAVAgAAAA==.Violetnoir:BAAALgAECgQJBAABLgAECgcJGgAbANsIAA==.Visiroth:BAAALgAECggJEQAAAA==.',
Vy='Vyyral:BAAALgAECgIJAgABLgAECgkJGQAgAC4aAA==.',
Wa='Wagyumoo:BAAALgAECgEJAQABLgAFFAMJBQAMAIkEAA==.Wallydk:BAABLgAECn8fAAIVAAkJcRVKKgAdAgAVAAkJcRVKKgAdAgAAAA==.Wanji:BAABLgAECn8jAAIVAAgJagdndgA9AQAVAAgJagdndgA9AQAAAA==.',
We='Weave:BAAALgADCgYJBgAAAA==.Wenesday:BAAALgADCgQJBAAAAA==.Westhresh:BAAALgADCgcJBwAAAA==.',
Wi='Widginatrix:BAAALgAECggJCwAAAA==.Willkain:BAAALgAECgMJAwAAAA==.',
Wo='Woah:BAAALgADCgYJBgABLgAECggJGQAbALkkAA==.Woons:BAAALgAECgIJBgAAAA==.',
Wr='Wraithbane:BAAALgAECgMJAwAAAA==.',
Xa='Xaya:BAABLgAECn8aAAMbAAcJ2wg7ewAWAQAbAAcJ2wg7ewAWAQAcAAQJ6AJJUQB6AAAAAA==.',
Xe='Xeralvezyn:BAAALgADCgkJCAAAAA==.',
Xi='Xiva:BAABLgAECn8cAAInAAYJNw+HJAAgAQAnAAYJNw+HJAAgAQAAAA==.',
Xo='Xovace:BAAALgAECgYJEgAAAA==.',
Xt='Xtayse:BAABLgAECn8YAAIDAAgJ0B3OAwAXAgADAAgJ0B3OAwAXAgAAAA==.',
Ya='Yagorbomb:BAAALgAECgEJAQAAAA==.Yamyam:BAABLgAECn8VAAIXAAkJsg/HKQCyAQAXAAkJsg/HKQCyAQAAAA==.',
Yi='Yirya:BAAALgADCgcJCAAAAA==.',
Yo='Yoruechi:BAACLgAFFH8FAAILAAMJRxwqBwAFAQALAAMJRxwqBwAFAQAuAAQKfykAAgsACAkoIxMDAL4CAAsACAkoIxMDAL4CAAAA.',
['Yú']='Yúmyúm:BAABLgAECn8kAAIHAAkJWBfWLQALAgAHAAkJWBfWLQALAgAAAA==.',
Za='Zahel:BAABLgAECn8lAAIHAAkJjR1NHABiAgAHAAkJjR1NHABiAgAAAA==.Zahrogue:BAAALgADCgYJBgABLgAECgkJJQAHAI0dAA==.Zalark:BAAALgADCgUJCgABLgAECggJJwAGABoUAA==.Zangai:BAAALgADCgUJBQAAAA==.',
Ze='Zeneri:BAABLgAECn8nAAMkAAkJEhAaHgC8AQAkAAkJEhAaHgC8AQAYAAUJKwsjNQDsAAAAAA==.',
Zo='Zobi:BAAALgAECgMJBQAAAA==.Zodius:BAAALgADCgEJAQAAAA==.Zomboo:BAAALgAFFAEJAQAAAA==.',
Zu='Zugzugzug:BAAALgADCgMJBgAAAA==.',
['Zò']='Zònan:BAAALgADCgEJAQABLgAECgkJKAASALITAA==.',
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
