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

local lookup = {'Hunter-Survival','Druid-Guardian','Paladin-Holy','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Paladin-Protection','DemonHunter-Vengeance','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Devourer','Unknown-Unknown','DeathKnight-Unholy','Hunter-BeastMastery','Druid-Restoration','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Subtlety','Shaman-Enhancement','Warrior-Arms','Mage-Frost','Druid-Balance','Priest-Shadow','Monk-Windwalker','Priest-Discipline','Priest-Holy','Druid-Feral','Shaman-Elemental','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abberleigh:BAAALgAECgMJBQAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgADCgcJBwAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAAALgAECgMJCAABLgAECggJOAABAIUfAA==.Alarlia:BAABLgAECn8jAAICAAgJvgt8GwDwAAACAAgJvgt8GwDwAAAAAA==.Alathor:BAAALgAECgEJAQAAAA==.Algonq:BAAALgADCggJFAABLgAECgYJHQADABoGAA==.Alliesofevil:BAABLgAECn8hAAIEAAgJ7BE2LABTAQAEAAgJ7BE2LABTAQAAAA==.Allsar:BAABLgAECn8ZAAICAAkJnR1zAwCjAgACAAkJnR1zAwCjAgAAAA==.Alsar:BAAALgAECgQJBgABLgAECgkJGQACAJ0dAA==.Alssar:BAAALgAECgYJCgAAAA==.',
Am='Amathushhg:BAABLgAECn9IAAQFAAkJGRchBQDOAQAGAAkJ9hNIMQDUAQAFAAgJ0hchBQDOAQAHAAIJ+gvKJgAyAAAAAA==.Amaunet:BAAALgADCgUJBQAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAAALgAECgcJEQAAAA==.Andreth:BAAALgAECgMJCAAAAA==.Anoxyn:BAAALgADCgEJAQAAAA==.Anthe:BAAALgADCgkJFwAAAA==.Anzul:BAABLgAECn8wAAMIAAkJTh9TFwB4AgAIAAkJPB5TFwB4AgAJAAUJxR2CEQBUAQAAAA==.',
Ar='Araestirra:BAAALgAECgYJEgAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAQJDAAGAGwBAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8WAAIKAAgJ6hSYCwCjAQAKAAgJ6hSYCwCjAQABLgAECgkJGQACAJ0dAA==.Arntdorn:BAAALgADCgEJAQAAAA==.Arroes:BAABLgAECn8ZAAILAAgJGB9nDQBgAgALAAgJGB9nDQBgAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgAECgMJAwAAAA==.',
Ay='Ayroona:BAABLgAECn8pAAIMAAkJOgoQNQB/AQAMAAkJOgoQNQB/AQAAAA==.',
Az='Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8OAAINAAQJJBveCwA7AQANAAQJJBveCwA7AQAuAAQKfy0AAg0ACAlRG3cOAM0BAA0ACAlRG3cOAM0BAAAA.Barbaydos:BAAALgADCggJCQAAAA==.Basement:BAABLgAECn8YAAIOAAcJDB3OJQDuAQAOAAcJDB3OJQDuAQAAAA==.',
Be='Beastnite:BAAALgADCggJHQABLgADCgkJEQAPAAAAAA==.Bellaburger:BAAALgAFFAQJBAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgEJAQABLgAECgkJKQAGAI8XAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAABLgAECn8fAAIEAAYJnAXwSgDHAAAEAAYJnAXwSgDHAAAAAA==.Biped:BAABLgAECn8lAAIHAAgJog9GCAB6AQAHAAgJog9GCAB6AQAAAA==.Birill:BAAALgAECgEJAQAAAA==.',
Bl='Blackdeath:BAACLgAFFH8FAAIQAAIJSglXnQCNAAAQAAIJSglXnQCNAAAuAAQKfyEAAhAACAlRFVViAMwBABAACAlRFVViAMwBAAAA.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Boomstique:BAABLgAECn8fAAIRAAYJHhjDUABWAQARAAYJHhjDUABWAQAAAA==.Boondocka:BAAALgAECgUJDQAAAA==.',
Br='Brewco:BAACLgAFFH8HAAISAAMJqRiJNgCVAAASAAMJqRiJNgCVAAAuAAQKfy0AAxIACAnRHqYUAJACABIACAnRHqYUAJACAAIABQl5D+0hALsAAAAA.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAABLgAECn8eAAIRAAgJlRFPOQCkAQARAAgJlRFPOQCkAQAAAA==.',
Bt='Btrain:BAABLgAECn8XAAMJAAYJNwlaJgCRAAAIAAYJOgbs0QCcAAAJAAUJrwpaJgCRAAAAAA==.',
['Bó']='Bóunty:BAABLgAECn8bAAQBAAcJwx+3EwDBAQABAAcJrR23EwDBAQARAAQJNx5HXgBNAQATAAEJPgJtmAAeAAAAAA==.',
Ca='Camaryn:BAAALgADCgIJAgAAAA==.Canadia:BAAALgAECgQJBgAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cattnip:BAAALgAECgEJAQAAAA==.Cavisch:BAABLgAECn8pAAMGAAkJjxc+LwDdAQAGAAkJjxc+LwDdAQAHAAIJGA4BHACTAAAAAA==.',
Ce='Cedric:BAAALgADCgMJAwAAAA==.Cenobité:BAABLgAECn8dAAIUAAgJiBCkCgBPAQAUAAgJiBCkCgBPAQAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgAECgEJAQABLgAECgcJGAAOAAwdAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIVAAMJlBUmDQAVAQAVAAMJlBUmDQAVAQAAAA==.Charmeleon:BAAALgAECggJDwAAAA==.Charmin:BAAALgADCgUJBQAAAA==.',
Ci='Cirax:BAABLgAECn8bAAIRAAYJXhV/VgBFAQARAAYJXhV/VgBFAQAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Clenton:BAABLgAECn87AAIJAAkJzQlYEwA9AQAJAAkJzQlYEwA9AQAAAA==.Clipper:BAAALgADCgYJBgAAAA==.',
Co='Cobrakai:BAAALgAECgIJAgAAAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8JAAIOAAQJNhkLIQBEAQAOAAQJNhkLIQBEAQAuAAQKfyYAAg4ACAlCIR4iAIQCAA4ACAlCIR4iAIQCAAAA.Cronnan:BAAALgAECgQJBAAAAA==.Crowford:BAABLgAECn8fAAIRAAcJiBDnUgBPAQARAAcJiBDnUgBPAQAAAA==.',
Cy='Cyris:BAAALgADCgkJKwABLgAECgYJHwAWAG0EAA==.',
['Cá']='Cástle:BAAALgAECgEJAQABLgAECgcJGAAOAAwdAA==.',
Da='Daemonfaust:BAAALgAECgQJCgAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dak:BAABLgAECn8YAAIQAAgJ6xPmRQCpAQAQAAgJ6xPmRQCpAQABLgAECggJGwAIAJIYAA==.Dalsar:BAAALgADCgcJBwAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECgYJHwAJAJkgAA==.Darkmiza:BAACLgAFFH8MAAIGAAQJbAHkawCcAAAGAAQJbAHkawCcAAAuAAQKfzsAAwYACAl1EQVIAIQBAAYACAl1EQVIAIQBAAUAAglDC0lYAGYAAAAA.Darkseer:BAAALgAECgQJCwAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8UAAIIAAYJBBbfcQCYAQAIAAYJBBbfcQCYAQAAAA==.',
De='Deadmangalad:BAABLgAECn8ZAAMUAAYJawayEwC9AAAUAAYJawayEwC9AAANAAEJFARUTAAZAAAAAA==.Deathnotes:BAAALgADCgEJAQAAAA==.Deathquina:BAAALgAECgMJAwAAAA==.Deedees:BAAALgAECgYJEAAAAA==.Demonbo:BAABLgAECn8ZAAIOAAgJiBQZRQBpAQAOAAgJiBQZRQBpAQAAAA==.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Deo:BAACLgAFFH8NAAMEAAQJWxkgEwAyAQAEAAQJAxYgEwAyAQAXAAMJMBS4EQDdAAAuAAQKfzAAAwQACAmWI0kMAPYCAAQACAmWI0kMAPYCABcAAgmNDS9DAFIAAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8nAAMRAAgJYhlFJwAcAgARAAgJYhlFJwAcAgABAAUJYQv8LADjAAAAAA==.Dessirius:BAAALgAECgEJAQAAAA==.Dethphalanax:BAAALgADCgUJCQAAAA==.',
Di='Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgADCgkJKQAAAA==.Diskbänk:BAAALgAECgUJBwAAAA==.',
Dk='Dkho:BAACLgAFFH8FAAIYAAMJ7gMHZADQAAAYAAMJ7gMHZADQAAAuAAQKfxUAAhgACAnCDVBWAJgBABgACAnCDVBWAJgBAAAA.',
Do='Dogminos:BAAALgADCgIJAgAAAA==.',
Dr='Drago:BAAALgAECgEJBAAAAA==.Dragontoast:BAAALgAECgMJCAAAAA==.Dral:BAEALgADCgkJKAAAAA==.Drphilyobody:BAABLgAECn8cAAIQAAcJCgi3fwAaAQAQAAcJCgi3fwAaAQAAAA==.Drui:BAABLgAECn8bAAIZAAgJXA4dNgBkAQAZAAgJXA4dNgBkAQAAAA==.Druidïan:BAAALgAECgEJAQAAAA==.',
Du='Duelittle:BAABLgAECn8ZAAIaAAcJbwrNKwAhAQAaAAcJbwrNKwAhAQAAAA==.',
Dy='Dynwor:BAAALgAECgEJAQAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAAALgAECggJEgAAAA==.Eatmyfrontal:BAABLgAECn8sAAIYAAgJsxLiTwCqAQAYAAgJsxLiTwCqAQAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgIJAgABLgAECgMJBgAPAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgADCgcJCQAAAA==.',
Ep='Epikrate:BAABLgAECn8dAAMGAAcJUBncPgCiAQAGAAYJGBncPgCiAQAFAAMJ4hiqSACUAAAAAA==.',
Es='Escaper:BAABLgAECn8wAAIUAAgJhRPgBwCWAQAUAAgJhRPgBwCWAQAAAA==.',
Ex='Extrema:BAAALgAECgMJCAAAAA==.',
Ez='Ezsdruid:BAAALgAECgkJCQAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAQJDgAYADkZAA==.Fallenembers:BAACLgAFFH8OAAIYAAQJORlSKgBhAQAYAAQJORlSKgBhAQAuAAQKfzAAAhgACAlZJegSALICABgACAlZJegSALICAAAA.Famine:BAABLgAECn8dAAMQAAgJzwWBhQAPAQAQAAgJwwSBhQAPAQAUAAUJzAf7DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQAAAA==.',
Fh='Fhait:BAAALgADCgkJOwABLgAECgYJHwAbAFoKAA==.',
Fi='Firsttimepvp:BAACLgAFFH8HAAIVAAIJJg0JIQCdAAAVAAIJJg0JIQCdAAAuAAQKfx0AAhUACAk/F/kXAIIBABUACAk/F/kXAIIBAAAA.',
Fl='Flow:BAAALgADCgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgUJCQAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Galadan:BAAALgADCgkJEAAAAA==.Gaskelmarg:BAAALgADCgkJFwAAAA==.',
Gh='Ghosty:BAABLgAECn8hAAQcAAkJIxXXEwDoAQAcAAkJsxHXEwDoAQAdAAcJpAuKTgD+AAAaAAEJcAEEbwAZAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAECggJIwAFANYgAA==.',
Gi='Gigaweed:BAAALgAECgYJBwABLgAECggJIwAFANYgAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtusk:BAABLgAECn8XAAIeAAgJKxDIDQB5AQAeAAgJKxDIDQB5AQAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAABLgAECn8dAAIGAAcJehVRSACDAQAGAAcJehVRSACDAQAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Gryphone:BAAALgADCgkJDQAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAgAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgADCggJDQABLgAECgYJHwAJAJkgAA==.',
Ha='Hakmud:BAAALgADCgYJCwAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hercyderc:BAAALgAECgEJAQABLgAFFAIJBQAOADYgAA==.Hettokal:BAAALgADCgcJBwAAAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAABLgAECn8ZAAIOAAgJ8hEoQgBzAQAOAAgJ8hEoQgBzAQAAAA==.Hondojoe:BAACLgAFFH8NAAIdAAQJNx6qCQBPAQAdAAQJNx6qCQBPAQAuAAQKfzAAAx0ACAmgIkoLAJsCAB0ACAmgIkoLAJsCABwAAgnYBptNAE4AAAAA.Honeydrake:BAAALgAECgIJAgAAAA==.Hopewell:BAABLgAECn8dAAIDAAYJGgYjQwDfAAADAAYJGgYjQwDfAAAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAABLgAECn8fAAIKAAYJrQk8FQCxAAAKAAYJrQk8FQCxAAABLgAECgYJHwAbAFoKAA==.Huhu:BAABLgAECn8ZAAIEAAkJrxSmGgDJAQAEAAkJrxSmGgDJAQAAAA==.Huma:BAAALgAECgYJEAAAAA==.Hundreg:BAAALgADCgYJBQAAAA==.',
Ib='Ibn:BAABLgAECn8iAAIXAAgJrQrpGQAwAQAXAAgJrQrpGQAwAQAAAA==.',
Ic='Icyhot:BAAALgADCgUJCAAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
Il='Illaris:BAAALgADCgIJAgAAAA==.',
In='Infiniity:BAAALgAECgMJCQAAAA==.',
Ir='Irielle:BAAALgAECgQJBAAAAA==.',
Is='Ishanllin:BAAALgADCgUJBQAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8iAAIOAAkJyRdyHwATAgAOAAkJyRdyHwATAgAAAA==.Ivylyn:BAAALgADCgYJDAAAAA==.',
Ix='Ixiyá:BAABLgAECn8nAAMMAAgJ8h6yFQBnAgAMAAcJayKyFQBnAgAfAAEJzgjheQAsAAAAAA==.Ixií:BAAALgADCgUJBQAAAA==.Ixì:BAABLgAECn8VAAISAAcJ1x17GAA6AgASAAcJ1x17GAA6AgAAAA==.',
Ja='Jakeyprogue:BAAALgAFFAEJAQABLgAFFAIJBAAPAAAAAA==.Jakota:BAAALgADCggJDAAAAA==.Jakskeleton:BAAALgAECgUJDgAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jaynamir:BAAALgAECgYJCwAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgADCgUJCAAAAA==.',
Jo='Joemacho:BAAALgADCgcJCAABLgAFFAQJDQAdADceAA==.Joshtee:BAAALgAECgIJAgAAAA==.Joslyn:BAAALgAECgQJBQAAAA==.',
Ju='Judax:BAABLgAECn81AAIfAAkJihoqDABXAgAfAAkJihoqDABXAgAAAA==.Justagirl:BAABLgAECn8fAAIbAAYJWgplNADiAAAbAAYJWgplNADiAAAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.',
Jy='Jymion:BAAALgADCgEJAQAAAA==.',
Ka='Kadooka:BAABLgAECn8aAAIRAAcJehJDVQBpAQARAAcJehJDVQBpAQAAAA==.Kahlyn:BAAALgAECgYJCwAAAA==.Kajax:BAABLgAECn8qAAIVAAgJISMwCAANAwAVAAgJISMwCAANAwAAAA==.Kaldaran:BAAALgAECgcJEwAAAA==.Karen:BAAALgADCgcJEQAAAA==.Karne:BAAALgADCgYJBgAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8cAAINAAYJzxqFGQA7AQANAAYJzxqFGQA7AQAAAA==.Keelay:BAABLgAECn8vAAIDAAgJAhscEQBDAgADAAgJAhscEQBDAgAAAA==.',
Kh='Kheegorn:BAABLgAECn8bAAIIAAgJkhhqTwDzAQAIAAgJkhhqTwDzAQAAAA==.Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwAPAAAAAA==.Kimiko:BAAALgADCgcJBwAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgAVACEjAA==.',
Ko='Koffcmorbius:BAAALgADCgYJDAAAAA==.Koriban:BAABLgAECn8iAAIYAAgJ+w9hWwCLAQAYAAgJ+w9hWwCLAQAAAA==.Korreban:BAAALgAECgYJBgABLgAECggJIgAYAPsPAA==.',
Kr='Kraken:BAABLgAECn8jAAIFAAgJ1iCpAQCAAgAFAAgJ1iCpAQCAAgAAAA==.',
Ku='Kubb:BAABLgAECn8fAAIWAAYJbQTTGAC9AAAWAAYJbQTTGAC9AAAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAACLgAFFH8MAAIeAAQJfR4CAgCGAQAeAAQJfR4CAgCGAQAuAAQKfyUAAh4ACQk4IxoFAMACAB4ACQk4IxoFAMACAAAA.',
['Kê']='Kêlsen:BAAALgAECgMJAwAAAA==.',
La='Lachupacabra:BAAALgADCgIJBAAAAA==.Larrissa:BAABLgAECn8ZAAMHAAYJFgbFEQDTAAAHAAYJFgbFEQDTAAAFAAEJggPhewAlAAAAAA==.Larry:BAAALgAECggJDgABLgAFFAQJCwAfAG8QAA==.Laurlynn:BAAALgADCgkJIAAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lenwe:BAAALgAECgMJAgABLgAECgYJJwAdAOoOAA==.Lettuceprey:BAABLgAECn8cAAIdAAYJYBJMKAA6AQAdAAYJYBJMKAA6AQAAAA==.',
Li='Lierise:BAAALgADCggJCAAAAA==.Lies:BAAALgADCgkJCQAAAA==.Lightsnipe:BAAALgAECgMJAwAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.',
Lo='Lockatute:BAAALgAECgcJCQAAAA==.Lockdeath:BAAALgAECgQJBAAAAA==.Loric:BAAALgADCgkJCQAAAA==.Loxia:BAAALgAECgcJDQAAAA==.',
Lu='Lucille:BAAALgAFFAEJAgAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAABLgAECn8VAAMeAAYJ5RfrDwBSAQAeAAYJ5RfrDwBSAQASAAEJGwacvQAjAAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Magicdance:BAABLgAECn8mAAMMAAgJEhB+OQBpAQAMAAgJEhB+OQBpAQAfAAcJ6QjFTwAIAQAAAA==.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIeAAgJchK/CwACAgAeAAgJchK/CwACAgAAAA==.Majicbob:BAAALgAECgYJCgAAAA==.Maki:BAAALgAECgcJEgAAAA==.Mansion:BAAALgADCgMJBAABLgAECgcJGAAOAAwdAA==.Marilune:BAAALgADCggJCQAAAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgAECgEJAQAAAA==.',
Mc='Mctowlie:BAAALgAECgYJBwAAAA==.',
Me='Mehänemäntä:BAAALgAECgMJCAAAAA==.Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAAALgAECgcJEwAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mf='Mfdkidney:BAAALgAECgIJAgAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAECggJJgAMABIQAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgADCgcJDAAAAA==.Misericorde:BAACLgAFFH8NAAIbAAQJUySTAgCtAQAbAAQJUySTAgCtAQAuAAQKfzIAAhsACAkNJncDAPMCABsACAkNJncDAPMCAAAA.Misstreater:BAAALgAECgcJDAAAAA==.',
Mo='Momentomori:BAABLgAECn8gAAIGAAkJvghPTwBuAQAGAAkJvghPTwBuAQAAAA==.Monocerotis:BAAALgADCgcJBwAAAA==.Morishima:BAACLgAFFH8MAAIVAAMJrRqSFQAUAQAVAAMJrRqSFQAUAQAuAAQKfy0AAxUACAmZI9MHAGICABUACAmZI9MHAGICACAAAQkJFqIcAD8AAAAA.Morthis:BAABLgAECn8cAAMTAAYJYglfGQCmAAATAAUJgwpfGQCmAAABAAMJWgMwQgBOAAAAAA==.',
Mu='Multipàss:BAAALgADCgcJCgAAAA==.',
My='Mydarling:BAAALgAFFAIJAwAAAA==.Myris:BAABLgAECn8fAAIQAAgJyhoeMAD4AQAQAAgJyhoeMAD4AQAAAA==.',
Na='Naturalchi:BAABLgAECn8nAAMbAAgJkyQkBQDFAgAbAAgJ2iMkBQDFAgAhAAYJ7iJdEgDjAQAAAA==.',
Ne='Nefilion:BAAALgAECgQJCAAAAA==.Nemas:BAABLgAECn8dAAIJAAgJrhl5CQDhAQAJAAgJrhl5CQDhAQAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAABLgAECn8ZAAQiAAYJ9xWVCgAtAQAiAAYJJROVCgAtAQAjAAYJyw5JNwD6AAAkAAIJuQ2jQABlAAAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nightrunnêr:BAAALgADCggJCAABLgAECgYJHwAJAJkgAA==.Nineadin:BAACLgAFFH8LAAIDAAMJ2RZZHgDeAAADAAMJ2RZZHgDeAAAuAAQKfyMAAgMACAk2Hk0TAHgCAAMACAk2Hk0TAHgCAAAA.Nirvanas:BAABLgAECn8YAAIeAAgJ8QZnFgD9AAAeAAgJ8QZnFgD9AAAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn8nAAMdAAYJ6g74LQAUAQAdAAYJ6g74LQAUAQAaAAQJmQZZSwCsAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.North:BAAALgAECgYJBgAAAA==.',
Nu='Nuke:BAAALgAECgQJEAAAAA==.Nullspace:BAABLgAECn8dAAIdAAkJXxqLDABRAgAdAAkJXxqLDABRAgAAAA==.',
Ny='Nyxe:BAAALgADCgkJCQABLgAECggJGwAIAJIYAA==.',
['Ní']='Níght:BAABLgAECn85AAICAAgJKhckDAC0AQACAAgJKhckDAC0AQAAAA==.',
Oa='Oaken:BAAALgADCgkJCgAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Om='Ommû:BAAALgAECgMJCAAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAECggJIwAFANYgAA==.',
Pa='Pakeydk:BAAALgAFFAIJBAAAAA==.Palacia:BAAALgAECgUJBQAAAA==.Pancakedealr:BAAALgAECgUJEAAAAA==.Pancakeeater:BAAALgAECgQJBAAAAA==.',
Pe='Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgYJBgAAAA==.Petrichorica:BAAALgAECgUJBQAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Pintobeans:BAABLgAECn8XAAIRAAkJlQU8TQBgAQARAAkJlQU8TQBgAQAAAA==.',
Pl='Plutonix:BAAALgAECgMJBAAAAA==.',
Pr='Preachêr:BAAALgAECgEJAQABLgAECgYJHwAJAJkgAA==.',
Pu='Puuhceew:BAABLgAECn8dAAIdAAYJkxDoPQBCAQAdAAYJkxDoPQBCAQAAAA==.',
Qu='Quan:BAEALgADCgcJCQABLgADCgkJKAAPAAAAAA==.Quelaag:BAAALgADCgQJBAAAAA==.Quiescent:BAABLgAECn8WAAIOAAcJyxU1QQB2AQAOAAcJyxU1QQB2AQAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAABLgAECn8aAAMHAAcJ5yLdAwAFAgAHAAcJ5yLdAwAFAgAGAAEJAxFE9gA3AAABLgAFFAUJEgAKAMMmAA==.Ramanas:BAAALgAECgcJEQAAAA==.Randomizwe:BAABLgAECn8uAAIIAAkJsx5VEQCiAgAIAAkJsx5VEQCiAgAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Rawrnèss:BAAALgAECgkJBgAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Relearning:BAABLgAECn8fAAIGAAgJnQzkUQBnAQAGAAgJnQzkUQBnAQAAAA==.Resurgencê:BAABLgAECn8fAAIJAAYJmSAyDACrAQAJAAYJmSAyDACrAQAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAABLgAECn8eAAMIAAgJGxQ/XQBtAQAIAAcJChQ/XQBtAQAJAAEJfhSxNwA7AAAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgcJGAAOAAwdAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJEwAAAA==.Rotandroll:BAAALgAECgcJDgAAAA==.Rothema:BAAALgAECgYJEgAAAA==.Routh:BAAALgAECgEJAQAAAA==.',
Rw='Rwlmaster:BAABLgAECn8XAAINAAcJfRGwGgAvAQANAAcJfRGwGgAvAQAAAA==.',
Ry='Rynzia:BAACLgAFFH8OAAMjAAQJERJ2GgAoAQAjAAQJERJ2GgAoAQAiAAIJ5AjNBgCOAAAuAAQKfzIAAyMACAmxIWIMAE8CACMACAmxIWIMAE8CACIABwmkFPQWAIUBAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAAALgAECgMJCAAAAA==.Santose:BAAALgAECgEJAQAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAABLgAECn8ZAAIQAAgJuAkqZQBTAQAQAAgJuAkqZQBTAQAAAA==.Schmerz:BAAALgADCgUJBQAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECggJOAABAIUfAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAAALgAECgMJCAAAAA==.Seta:BAABLgAECn8bAAIOAAgJ2xNeQwDmAQAOAAgJ2xNeQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJBAAPAAAAAA==.Shamarha:BAAALgAECgcJEgAAAA==.Sharriavolf:BAABLgAECn85AAQGAAgJKCGRRgD3AQAGAAYJ1R6RRgD3AQAFAAQJciMLIABSAQAHAAEJAAB7IwBkAAAAAA==.Shato:BAAALgAECgYJCQAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shiori:BAAALgAECgYJBgAAAA==.Shortmedic:BAAALgAECgQJBAAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgADCgcJDAAPAAAAAA==.Siggismund:BAABLgAECn8XAAIIAAgJTgaFgQAgAQAIAAgJTgaFgQAgAQAAAA==.Simichaelton:BAABLgAECn8XAAIYAAgJRxGefABBAQAYAAgJRxGefABBAQABLgAECggJKwAbABQdAA==.Sinpal:BAAALgAECgIJBAABLgAECggJNgAGADcjAA==.Sioce:BAAALgADCggJBwAAAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgADCgYJBgAAAA==.',
Sm='Smorroy:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8eAAIIAAgJ/BxdSQAGAgAIAAgJ/BxdSQAGAgAAAA==.Sophrosyne:BAABLgAECn8UAAIRAAcJ2xOLSQBrAQARAAcJ2xOLSQBrAQAAAA==.Souless:BAAALgAECgYJBgAAAA==.',
Sp='Spartaaxd:BAABLgAECn8hAAIUAAkJKBAjCACPAQAUAAkJKBAjCACPAQAAAA==.Spookems:BAAALgAECgIJAgABLgAECgkJEQAPAAAAAA==.Spycy:BAAALgAECggJEwAAAA==.',
St='Stagerrind:BAAALgADCgQJBAAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8oAAIDAAkJOwzeJQCNAQADAAkJOwzeJQCNAQAAAA==.Stinkyfrog:BAABLgAECn8aAAIIAAcJFCCpJAAqAgAIAAcJFCCpJAAqAgAAAA==.Stovetop:BAAALgAECgEJAQABLgAECgUJBwAPAAAAAA==.Stubmcbean:BAAALgADCgEJAQABLgAECgYJHwAWAG0EAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8mAAIYAAkJOgtVdQBPAQAYAAkJOgtVdQBPAQAAAA==.Suka:BAAALgADCggJIQAAAA==.Surok:BAAALgAECgYJDwAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgcJDAAAAA==.',
Sy='Sylentcurse:BAAALgAECgcJDgABLgAECggJHgARAJURAA==.Sylentstorm:BAAALgAECgQJBQABLgAECggJHgARAJURAA==.Syleta:BAABLgAECn84AAQBAAgJhR/ODwDwAQARAAcJwxwNMADwAQABAAYJeh3ODwDwAQATAAYJCRNpRABEAQAAAA==.',
Ta='Tabraxis:BAAALgADCgcJBwAAAA==.Tagalorc:BAABLgAECn8YAAIlAAcJEhN3BABtAQAlAAcJEhN3BABtAQAAAA==.Takamaki:BAAALgAECgEJAQAAAA==.Tanksbacon:BAABLgAECn8cAAMIAAkJbxcSLQAEAgAIAAkJbxcSLQAEAgAJAAQJtxKSLwCWAAAAAA==.Taylith:BAAALgAECgYJBgAAAA==.',
Te='Teana:BAABLgAECn8WAAIUAAgJaQ16CgBTAQAUAAgJaQ16CgBTAQAAAA==.Teannev:BAAALgADCgYJBgAAAA==.Tempestas:BAAALgADCgkJEAAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAFFAMJBwASAKkYAA==.Thelegendáry:BAABLgAECn8XAAIMAAYJlhdBSgBZAQAMAAYJlhdBSgBZAQABLgAFFAMJCAAIAPoNAA==.Thetool:BAAALgAECgMJBAAAAA==.Thraine:BAAALgAECgYJCwAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAABLgAECn8gAAMZAAcJjR3nGwCPAQAZAAYJnxznGwCPAQASAAcJZgmpawCuAAAAAA==.',
To='Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAABLgAECn8VAAIfAAgJMAgRPQDnAAAfAAgJMAgRPQDnAAAAAA==.Toto:BAAALgAECgkJAgAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Trisstan:BAABLgAECn8dAAMYAAYJZwbxrQDpAAAYAAYJZwbxrQDpAAAmAAMJawEvDQBVAAAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8iAAMYAAkJshtRJQBGAgAYAAkJkBhRJQBGAgAlAAUJHyAJBgDAAQAAAA==.Tyster:BAABLgAECn8eAAIIAAgJVxLkSwCaAQAIAAgJVxLkSwCaAQAAAA==.',
Uk='Ukyo:BAAALgADCgUJBgAAAA==.',
Ul='Ullidon:BAAALgAECgEJAQAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJFAABLgAECgYJHwAWAG0EAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECgkJIwAhAFgaAA==.',
Uz='Uzu:BAABLgAECn8jAAIhAAkJWBpkGwCNAQAhAAkJWBpkGwCNAQAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Valorr:BAAALgADCgUJBQAAAA==.Vamp:BAABLgAECn8WAAIMAAcJUhjxLwDIAQAMAAcJUhjxLwDIAQAAAA==.Vandaldor:BAAALgAECgYJDgAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8OAAIYAAQJ4RLsNwBJAQAYAAQJ4RLsNwBJAQAuAAQKfyoAAhgACAldIkIlAEcCABgACAldIkIlAEcCAAAA.',
Vh='Vhitahni:BAAALgAECgMJAwAAAA==.',
Vi='Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8kAAMRAAkJtRtvHQAnAgARAAkJtRtvHQAnAgABAAIJewTpKgBVAAAAAA==.',
Vy='Vynlorin:BAAALgAECgYJBgABLgAECgkJMAAIAE4fAA==.',
Wa='Wanawa:BAAALgAECgMJAwABLgAECggJFwAeACsQAA==.Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECggJFwAeACsQAA==.Warthog:BAAALgADCgYJCQAAAA==.Waterbender:BAABLgAECn8ZAAIMAAkJRRqcDgCPAgAMAAkJRRqcDgCPAgAAAA==.',
We='Weechuup:BAAALgADCggJEAAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wifeotusk:BAAALgAECgUJBQAAAA==.Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAAALgAECgYJEAAAAA==.Window:BAAALgADCgUJBQABLgAECgcJGAAOAAwdAA==.',
Wm='Wmdplague:BAAALgADCgYJBgAAAA==.',
Wo='Wolf:BAABLgAECn8eAAICAAgJpxb+CwDMAQACAAgJpxb+CwDMAQAAAA==.Wolfton:BAAALgADCgcJDQAAAA==.',
Wr='Wrekkit:BAAALgAECgcJBwAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMRAAgJIhvAHQBTAgARAAgJIhvAHQBTAgATAAMJrAJgdABtAAAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xu='Xuchilbara:BAABLgAECn8cAAIeAAcJdhcwDACWAQAeAAcJdhcwDACWAQAAAA==.',
Xy='Xyro:BAAALgAECgUJBQABLgAECggJGwAIAJIYAA==.',
Ya='Yamato:BAAALgAECgYJCwAAAA==.',
Za='Zaledron:BAABLgAECn8ZAAIQAAcJzx5yPgDCAQAQAAcJzx5yPgDCAQAAAA==.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAABLgAECn8YAAMWAAcJZQuQEgATAQAWAAcJZQuQEgATAQAMAAIJ+gq2jABiAAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8KAAMQAAMJJR2bVQAEAQAQAAMJJR2bVQAEAQAUAAEJBgLMEgA9AAAuAAQKfzsAAxAACQlmJDwGABkDABAACQlmJDwGABkDABQACAkfH94CAGICAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgADCgcJCwABLgADCgcJDAAPAAAAAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.Zomby:BAAALgAECgQJBAABLgAECggJKwAbABQdAA==.',
Zp='Zpersephone:BAAALgAECgYJDgABLgAFFAMJCgAQACUdAA==.',
Zr='Zrii:BAAALgAECgMJAwAAAA==.',
Zu='Zultan:BAACLgAFFH8GAAIGAAQJugayQgABAQAGAAQJugayQgABAQAuAAQKfyYAAwYACAmzEiA/AKEBAAYABwmzEiA/AKEBAAUAAQkAAI4+AAAAAAAA.Zurrik:BAABLgAECn8qAAIZAAgJ1BF3IABoAQAZAAgJ1BF3IABoAQAAAA==.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8GAAIhAAMJqBTYEgDjAAAhAAMJqBTYEgDjAAAuAAQKfycAAyEACAmEHzsJAPUCACEACAmEHzsJAPUCABsAAwkjGUJrADkAAAAA.',
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
