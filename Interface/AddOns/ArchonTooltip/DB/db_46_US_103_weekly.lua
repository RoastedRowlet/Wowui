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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Holy','Paladin-Holy','Shaman-Restoration','Hunter-BeastMastery','Warrior-Arms','Warrior-Fury','Warrior-Protection','Warlock-Destruction','Hunter-Marksmanship','Unknown-Unknown','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Druid-Restoration','DeathKnight-Blood','Paladin-Retribution','Shaman-Elemental','Mage-Frost','Priest-Shadow','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Monk-Mistweaver','Druid-Feral',}
local provider = {region='US',realm='Garithos',name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Abolition:BAAALgAECgcJBQAAAA==.',
Ac='Aciersilva:BAAALgAECgUJCQAAAA==.',
Ae='Aemeath:BAACLgAFFH84AAIBAAkJiR6KAAASAwABAAkJiR6KAAASAwAuAAQKfxYAAwEACQkaJQsBALcDAAEACQkaJQsBALcDAAIAAQmsHs4qAFcAAAAA.',
Aj='Ajtwo:BAACLgAFFH8UAAIDAAUJxw2bHwAnAQADAAUJxw2bHwAnAQAuAAQKfykAAwMACQnbFzMXAOIBAAMACQnbFzMXAOIBAAQAAwmwBLQZAF8AAAAA.',
Ak='Akanbe:BAABLgAECn85AAIFAAkJ9B3/BwD4AgAFAAkJ9B3/BwD4AgAAAA==.Akenos:BAAALgAECgIJAwAAAA==.',
Al='Aloevera:BAAALgAECgYJBgABLgAFFAMJEgAFAHobAA==.',
An='Anniichan:BAACLgAFFH8IAAIGAAMJYgydEwCEAAAGAAMJYgydEwCEAAAuAAQKfygAAwYACQnaCm4uAFoBAAYACQnaCm4uAFoBAAUAAQnlAR5fACEAAAAA.Anxious:BAACLgAFFH8SAAIHAAgJDBP4FQB4AQAHAAgJDBP4FQB4AQAuAAQKfxsAAgcACAlsFkYxAJIBAAcACAlsFkYxAJIBAAAA.',
Ar='Areyna:BAAALgADCgIJAgAAAA==.Arqus:BAAALgADCgEJAQAAAA==.',
Aw='Awake:BAAALgADCgYJBwAAAA==.',
Az='Azaera:BAAALgAECgYJCAAAAA==.',
Ba='Badgrammer:BAAALgAFFAIJAgAAAA==.Bandaidbessy:BAAALgAECgEJAQABLgAFFAQJCAAIALoGAA==.',
Be='Beefmissile:BAAALgAECgYJCQAAAA==.',
Bi='Bill:BAAALgAECgYJDAAAAA==.',
Bl='Blitter:BAAALgAECgMJAwAAAA==.Bloodbath:BAAALgADCgYJEgAAAA==.Bloødÿ:BAAALgAECgcJEQAAAA==.',
Bo='Bosephis:BAABLgAECn89AAIJAAkJ8ReYCAD/AQAJAAkJ8ReYCAD/AQAAAA==.',
Bu='Bubsecute:BAABLgAECn8bAAQKAAkJjBhpDAAgAgAKAAkJjBhpDAAgAgALAAMJmgsCgwBuAAAMAAEJxBtLSwBJAAAAAA==.Bunkerbawb:BAAALgAECgQJBAAAAA==.Buu:BAAALgAECgcJDAAAAA==.',
Cl='Cleanshaven:BAAALgADCgEJAQAAAA==.',
Co='Combatlog:BAAALgAECgUJBQAAAA==.',
Cr='Crabdaddy:BAAALgAECgQJCgAAAA==.Cranberries:BAAALgAECgYJEAAAAA==.',
Ct='Ctarnidd:BAAALgAECgUJCwAAAA==.',
Da='Dantë:BAAALgAECgMJBAAAAA==.Daxs:BAAALgADCgkJDQAAAA==.',
De='Deathlyropes:BAAALgADCgIJAgAAAA==.Dehumanized:BAAALgADCgYJBgAAAA==.',
Di='Diananight:BAABLgAECn8pAAINAAkJAgjnFwDjAAANAAkJAgjnFwDjAAAAAA==.Dinorèy:BAAALgAECgEJAQAAAA==.',
Dk='Dkaela:BAAALgAECgQJBQAAAA==.',
Dr='Dredaton:BAAALgADCgEJAQAAAA==.Drogahn:BAAALgAECgYJEAAAAA==.Drpuñetazos:BAABLgAECn8WAAIHAAcJzQpJRwBbAQAHAAcJzQpJRwBbAQAAAA==.',
Du='Dumbldorian:BAAALgADCgUJBQAAAA==.Dumblebob:BAAALgADCgYJHwAAAA==.Dumbledoe:BAAALgADCgUJDgAAAA==.Dumbledor:BAAALgADCgYJGgAAAA==.Dumblehunt:BAAALgADCgYJFwAAAA==.Dumblepal:BAAALgADCgYJEwAAAA==.Dumblepow:BAAALgADCgYJFwAAAA==.Dumblesham:BAAALgADCgYJHAAAAA==.Dustocky:BAAALgAECgcJDgAAAA==.Dustyggonar:BAAALgADCgEJAQAAAA==.',
El='Elaina:BAACLgAFFH8TAAIJAAUJ4BWDPAA0AQAJAAUJ4BWDPAA0AQAuAAQKfxsAAw4ACQlsG1olAP0BAA4ACAn1E1olAP0BAAkABAm+JJyEADUBAAAA.Element:BAAALgAECgEJAQABLgAECgcJEwAPAAAAAA==.',
Ev='Evoke:BAAALgAECgYJBgABLgAFFAUJCQAQAC0SAA==.',
Ez='Ezhammered:BAAALgAECgUJCAABLgAECgkJGwARAP4dAA==.',
Fl='Flight:BAAALgAECgIJAgABLgAECgcJEwAPAAAAAA==.Flokifindel:BAAALgAECgYJDAAAAA==.Flokiflex:BAAALgADCgEJAQAAAA==.Flokighoul:BAAALgAECggJCQAAAA==.Flokisaurus:BAAALgAECgEJAgAAAA==.Flokivaelar:BAAALgAECgMJAwAAAA==.Flokizuul:BAAALgADCgYJBgAAAA==.Florescence:BAACLgAFFH8JAAISAAQJiBlLGgBHAQASAAQJiBlLGgBHAQAuAAQKfzEAAxIACQmZIFAKAK8CABIACQmZIFAKAK8CABMABgl9E3dSAF0BAAAA.',
Fo='Fox:BAABLgAECn8XAAISAAYJIQtYTQDXAAASAAYJIQtYTQDXAAAAAA==.',
Fr='Fractalella:BAAALgAECgEJAQAAAA==.Frakattack:BAAALgADCgkJGQAAAA==.Frostlord:BAAALgAECgcJDgABLgAFFAEJAgAPAAAAAA==.Frymancer:BAABLgAECn8VAAIUAAcJ2QyfMgDSAAAUAAcJ2QyfMgDSAAAAAA==.',
Go='Goemon:BAAALgAECgYJEQAAAA==.Gorc:BAAALgAECgEJAQAAAA==.',
Gr='Grimtheorist:BAAALgADCgUJBQAAAA==.',
Gu='Gummychaos:BAAALgAECggJCwAAAA==.Gummypriest:BAAALgADCgMJAwAAAA==.',
He='Hellion:BAAALgAECgYJCQAAAA==.Hendrick:BAAALgADCgYJCwAAAA==.',
Ho='Hozz:BAABLgAECn8aAAIVAAYJTgdUMwCKAAAVAAYJTgdUMwCKAAAAAA==.',
Hu='Hudemonized:BAAALgAECgcJDAAAAA==.',
Id='Idiotbox:BAAALgAECgUJBQABLgAECgkJQAALABYKAA==.',
Il='Illestofdans:BAAALgAECgQJBAAAAA==.',
In='Inanis:BAAALgAECgMJAwAAAA==.Incinerate:BAAALgAECgEJAQABLgAECgcJEwAPAAAAAA==.',
Ir='Ironfistt:BAAALgAECgMJAwAAAA==.',
Iy='Iyaman:BAAALgADCgcJBwAAAA==.',
Je='Jelgava:BAAALgAECgEJAQAAAA==.',
Ji='Jinx:BAACLgAFFH8sAAIBAAgJIyLHAQBvAgABAAgJIyLHAQBvAgAuAAQKfxYAAgEACAnhHh8LAK8CAAEACAnhHh8LAK8CAAEuAAUUCQk4AAEAiR4A.',
Ju='Julian:BAAALgAECgYJEgAAAA==.Jumbohines:BAAALgAECgUJBgAAAA==.',
Ka='Kaela:BAAALgAECgUJDAAAAA==.Kaleela:BAAALgAECgYJDgAAAA==.Kalicat:BAAALgAECgIJAgABLgAECgkJGwARAP4dAA==.Kammulus:BAAALgAECgQJBAAAAA==.Kanyequest:BAAALgAECggJDAABLgAFFAQJCAAIALoGAA==.Kayde:BAAALgAECggJCwAAAA==.',
Ke='Keepitscruby:BAAALgAECgMJAwABLgAFFAQJCAAIALoGAA==.Keisel:BAABLgAECn8bAAMIAAgJ5xPbMwDiAQAIAAgJ5xPbMwDiAQAWAAEJuweCtwAlAAAAAA==.Kerevon:BAAALgADCgMJAwAAAA==.',
Ki='Killingusall:BAAALgAECgcJDgAAAA==.Kissmyheals:BAABLgAECn8UAAIIAAcJoQr+dgD5AAAIAAcJoQr+dgD5AAAAAA==.',
Ku='Kuromi:BAAALgAECgQJBwAAAA==.',
Ky='Kyomi:BAAALgAECgEJAQAAAA==.',
La='Landorath:BAAALgADCgUJBQAAAA==.',
Le='Legendairy:BAAALgAECgkJCQABLgAECgkJGwARAP4dAA==.Lemmejust:BAAALgAECgUJBQAAAA==.',
Li='Lightfall:BAABLgAECn8qAAIVAAkJ2xLSDACbAQAVAAkJ2xLSDACbAQAAAA==.Lilbigterd:BAABLgAECn8xAAIVAAgJ+RydMQBcAgAVAAgJ+RydMQBcAgAAAA==.Linithel:BAAALgADCgkJIgAAAA==.',
Lo='Locky:BAAALgADCgEJAQAAAA==.',
Lu='Lukaga:BAABLgAECn9AAAILAAkJFgrCCwAQAQALAAkJFgrCCwAQAQAAAA==.Luxray:BAAALgAECgQJBAAAAA==.',
Ly='Lychee:BAAALgAECgcJDQAAAA==.',
Ma='Magilou:BAABLgAFFH8TAAIXAAgJRBC1KgDJAQAXAAgJRBC1KgDJAQAAAA==.Mali:BAABLgAECn8bAAISAAgJxgzgDADsAAASAAgJxgzgDADsAAAAAA==.Mandalor:BAAALgAECgQJDQAAAA==.Maple:BAACLgAFFH8JAAIJAAIJmCSxEADDAAAJAAIJmCSxEADDAAAuAAQKfx4AAwkACAnlIjkYAHcCAAkACAnlIjkYAHcCAA4ABQl6FVlAAFgBAAAA.Marionetta:BAAALgAECgQJBwAAAA==.Maxipriest:BAABLgAECn8XAAMFAAYJLwTDTwDEAAAFAAYJLwTDTwDEAAAYAAQJYASpcABhAAAAAA==.',
Md='Mdsnista:BAABLgAECn+aAAIXAAkJvSHlAgDvAgAXAAkJvSHlAgDvAgAAAA==.',
Me='Meiffert:BAAALgADCgUJBQABLgAECgkJPQAJAPEXAA==.',
Mi='Mikiel:BAAALgAECgEJAQABLgAECgYJEAAPAAAAAA==.Milff:BAAALgADCgYJBwAAAA==.Minouimu:BAABLgAECn8YAAIZAAgJEAbGGwCuAAAZAAgJEAbGGwCuAAABLgAECgkJQAALABYKAA==.',
Mo='Mope:BAAALgADCgcJBwAAAA==.Mossyleaf:BAAALgAECgQJBAAAAA==.',
My='Mythic:BAAALgAECgQJBAAAAA==.',
Na='Naeblis:BAABLgAECn8lAAIZAAgJNxGAXgBtAQAZAAgJNxGAXgBtAQAAAA==.',
Ne='Nerox:BAAALgAECgcJDgAAAA==.Neryssa:BAABLgAECn8qAAIaAAkJmAvZBAA4AQAaAAkJmAvZBAA4AQAAAA==.',
No='Notillidan:BAAALgADCgcJBwABLgAECgMJBAAPAAAAAA==.',
Nu='Nuggetman:BAABLgAECn8vAAIaAAgJKAvqFgBVAQAaAAgJKAvqFgBVAQAAAA==.Nukacola:BAAALgAECgQJBwAAAA==.',
Of='Ofortuna:BAAALgAECgEJAgAAAA==.',
Ov='Overman:BAAALgAECgQJBwAAAA==.',
Oz='Ozric:BAAALgADCgEJAwAAAA==.',
Pa='Pak:BAAALgAECgEJAQAAAA==.Paldorei:BAAALgADCgYJBgABLgAECgMJBAAPAAAAAA==.Patience:BAABLgAECn8VAAIDAAcJsAMANgD9AAADAAcJsAMANgD9AAAAAA==.Paulette:BAAALgAECgUJDQAAAA==.',
Pl='Plant:BAABLgAECn9iAAITAAkJQiHpAABKAwATAAkJQiHpAABKAwAAAA==.',
Qm='Qmen:BAACLgAFFH8PAAMVAAQJrgjpWQD8AAAVAAQJrgjpWQD8AAAHAAIJlQUgIgBRAAAuAAQKfzUAAxUACQmRGdwQAGMBABUACQmRGdwQAGMBAAcAAQn2BhyVACoAAAAA.',
Qt='Qtora:BAABLgAECn8bAAQaAAcJBBhiBABKAQAaAAUJuRZiBABKAQAWAAUJehjaCgAdAQAIAAUJNxHQigDFAAAAAA==.',
Qu='Queso:BAACLgAFFH8SAAIFAAMJehv0FADsAAAFAAMJehv0FADsAAAuAAQKfzAAAwUACQl3GSEgAMwBAAUACQl3GSEgAMwBAAYAAwmVBphsAHcAAAAA.',
Ra='Radius:BAAALgAECgEJAQAAAA==.Raider:BAAALgAECgcJEgAAAA==.Raindrop:BAAALgAECgUJCAAAAA==.Raitech:BAAALgADCgEJAQAAAA==.Raxxar:BAACLgAFFH8NAAIJAAUJiRxmLABZAQAJAAUJiRxmLABZAQAuAAQKfzYAAgkACQmPIakXAJkCAAkACQmPIakXAJkCAAAA.',
Ru='Ruf:BAAALgAECgYJBgAAAA==.Rug:BAAALgAECgUJCgAAAA==.',
Sa='Sam:BAAALgAECgUJBQAAAA==.Sanctalux:BAAALgAECgYJBgAAAA==.Saraian:BAAALgAECgYJCgAAAA==.',
Sc='Scrubby:BAAALgAECgUJCgABLgAFFAQJCAAIALoGAA==.',
Se='Sean:BAAALgAECgUJBwAAAA==.Semtéc:BAAALgAECgIJBAAAAA==.Sephîroth:BAAALgAECgYJCgAAAA==.',
Sh='Shadont:BAABLgAECn8fAAIYAAkJRxMlHgDUAQAYAAkJRxMlHgDUAQAAAA==.Shamone:BAAALgAECgMJBAAAAA==.Shaquiloheal:BAACLgAFFH8IAAMIAAQJugb+OABpAAAIAAQJugb+OABpAAAWAAIJNQPITgBcAAAuAAQKfzEAAxYACAnpFHsnALEBABYACAnpFHsnALEBAAgABglsF2BCAKQBAAAA.',
Si='Sinhfyre:BAABLgAECn89AAMbAAkJ9wjhAgAAAQAbAAkJ9wjhAgAAAQAcAAYJXQJJdQB8AAAAAA==.',
Sl='Slayerofman:BAAALgADCgEJAQAAAA==.Sleepi:BAAALgAECgYJEAAAAA==.Sliverr:BAABLgAECn8ZAAISAAgJMAYoSgDjAAASAAgJMAYoSgDjAAAAAA==.',
Sm='Smex:BAAALgAECgMJAwAAAA==.Smokingbonez:BAAALgADCgIJAgAAAA==.Smyrna:BAAALgAECgMJAwAAAA==.',
So='Somberburden:BAABLgAECn8bAAMRAAkJ/h3lDABoAgARAAgJhyDlDABoAgAQAAkJcxNNMgA8AQAAAA==.',
Sp='Spippifist:BAAALgADCgEJAQAAAA==.Spippippik:BAAALgAECgUJDAAAAA==.Spotter:BAAALgAECgYJCAAAAA==.',
St='Stayinscruby:BAAALgAECgUJDQABLgAFFAQJCAAIALoGAA==.Stillscruby:BAACLgAFFH8JAAIDAAQJxwWkEwDlAAADAAQJxwWkEwDlAAAuAAQKfygAAgMACQmCEF0ZAM8BAAMACQmCEF0ZAM8BAAEuAAUUBAkIAAgAugYA.',
Su='Sumting:BAABLgAECn8UAAMTAAcJTgfRcwDaAAATAAcJTgfRcwDaAAASAAIJAgMupwAZAAAAAA==.',
['Sí']='Síntor:BAABLgAECn8+AAMVAAkJExoELABRAgAVAAkJoRgELABRAgAdAAYJABXRHgAdAQAAAA==.',
Te='Teach:BAABLgAECn8VAAMeAAcJBBaaPQB5AQAeAAcJBBaaPQB5AQAQAAQJihUJPwADAQABLgAECgYJFAAEABMdAA==.Tenjii:BAAALgAECgQJBAABLgAECgcJDwAPAAAAAA==.Tensham:BAAALgAECgcJDwAAAA==.',
Th='Theimpaler:BAABLgAECn8cAAMKAAcJOgxYLwALAQAKAAcJOgxYLwALAQAMAAEJnwMkTwAfAAABLgAFFAEJAgAPAAAAAA==.Thepalix:BAAALgAECgMJAwAAAA==.',
Tr='Traquility:BAAALgAECgcJEwAAAA==.Traumadealer:BAABLgAFFH8FAAIdAAMJmAg9CwBoAAAdAAMJmAg9CwBoAAAAAA==.',
Tw='Tweedlerun:BAACLgAFFH8JAAIQAAUJLRLQBABDAQAQAAUJLRLQBABDAQAuAAQKfyYAAhAACAnQIRAKANcCABAACAnQIRAKANcCAAAA.Twiks:BAAALgAECgYJEAAAAA==.',
Ul='Uley:BAEBLgAECn8dAAITAAgJLxbRAwAKAgATAAgJLxbRAwAKAgAAAA==.',
Um='Umamae:BAAALgADCgYJBgAAAA==.Umamoo:BAAALgADCgcJGgAAAA==.',
Vi='Vissarion:BAABLgAECn82AAINAAkJjxthAwBkAgANAAkJjxthAwBkAgAAAA==.',
Vo='Volker:BAACLgAFFH8KAAIMAAMJ8wuFFAB/AAAMAAMJ8wuFFAB/AAAuAAQKfx8AAgwACQmKEKYfADUBAAwACQmKEKYfADUBAAAA.',
Wa='Warlok:BAAALgAECgEJAQAAAA==.Waynekerr:BAAALgADCgEJAQABLgAFFAQJCAAIALoGAA==.Waywa:BAAALgAECgUJBQAAAA==.',
Wi='Witz:BAAALgAECgUJEQABLgADCgcJBwAPAAAAAQ==.',
Xa='Xandus:BAABLgAECn8rAAIBAAkJPyCaBwC3AgABAAkJPyCaBwC3AgAAAA==.Xandûs:BAABLgAFFH8MAAIZAAUJrw2XUAD7AAAZAAUJrw2XUAD7AAAAAA==.',
Xe='Xeraza:BAAALgAFFAIJAwABLgAFFAUJDgAdADMTAA==.Xerô:BAACLgAFFH8OAAMdAAUJMxMiBgAfAQAdAAUJMxMiBgAfAQAVAAEJdwGG0gAgAAAuAAQKfywAAx0ACAlEH1sIAFICAB0ACAlEH1sIAFICABUAAQmwF4Z4AUIAAAAA.',
Xu='Xubdragon:BAAALgADCgcJHAAAAA==.Xubpally:BAAALgADCgcJCwAAAA==.',
Ya='Yatogami:BAAALgAECggJEwAAAA==.',
Yi='Yindao:BAAALgADCgYJBgAAAA==.',
Yo='Yogo:BAABLgAECn8VAAIXAAcJMwX65ADTAAAXAAcJMwX65ADTAAAAAA==.',
Zu='Zuf:BAACLgAFFH8VAAISAAcJqRYyGQBQAQASAAcJqRYyGQBQAQAuAAQKfzYAAxIACQk5JVcCAFADABIACQk5JVcCAFADAB8AAQnfAic5ACQAAAAA.',
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
