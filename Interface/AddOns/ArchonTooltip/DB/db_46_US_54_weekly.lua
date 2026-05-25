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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warrior-Fury','Hunter-BeastMastery','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Rogue-Assassination','DemonHunter-Devourer','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Druid-Guardian','Warrior-Arms','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='weekly',zone=46,date='2026-05-23',data={Ae='Aendean:BAAALgAECgQJBAAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgIJAwABLgAECgYJCAABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn80AAMCAAkJqCAeFwBdAgACAAgJ4x8eFwBdAgADAAIJEBm/XgCWAAAAAA==.',
As='Asmadeus:BAAALgAECgYJBwAAAA==.',
Ay='Ayda:BAABLgAECn9FAAIEAAkJXyUZBABbAwAEAAkJXyUZBABbAwAAAA==.',
Ba='Bajabeachboy:BAAALgAFFAIJBAABLgAFFAMJDgAFAEofAA==.Bartholdson:BAABLgAECn8aAAIGAAgJ2hhkLwD1AQAGAAgJ2hhkLwD1AQAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgcJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8kAAIHAAkJfxxACQDSAgAHAAkJfxxACQDSAgAAAA==.',
Bo='Bonfire:BAACLgAFFH8HAAIIAAUJvRwIFQBiAQAIAAUJvRwIFQBiAQAuAAQKfyYABAgACQlvI9MJAJ8CAAgACQntItMJAJ8CAAkABgluIU0OAAgBAAoAAglKAoZEAEsAAAEuAAUUBQkJAAQAGRwA.Boochili:BAABLgAECn9BAAILAAkJ7yYHAACWAwALAAkJ7yYHAACWAwAAAA==.',
Br='Bravebeard:BAAALgAFFAMJAwAAAA==.Braveling:BAABLgAECn8ZAAIMAAgJOgxMYABqAQAMAAgJOgxMYABqAQAAAA==.',
Bu='Bubblës:BAAALgAECgQJCAABLgAECgkJMAAEAJgiAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8XAAMNAAYJ3CKKBwDtAQANAAYJ3CKKBwDtAQALAAEJQCNCDgBiAAAuAAQKfzgAAw0ACQnOJR8IAFMDAA0ACQnOJR8IAFMDAAsABQnOGfseAOwAAAAA.Chicken:BAAALgAFFAMJBAAAAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAACLgAFFH8JAAICAAQJuhe7HwAxAQACAAQJuhe7HwAxAQAuAAQKf10AAwIACQm7IJQFADMDAAIACQm7IJQFADMDAAMABgl3DspHAOQAAAAA.',
Da='Dagron:BAAALgAFFAIJAgAAAA==.Daniedk:BAABLgAECn8tAAIOAAgJvhNQWgCUAQAOAAgJvhNQWgCUAQAAAA==.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgYJEQAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMOAAMJPhwOewDcAAAOAAMJPhwOewDcAAAPAAIJSRAvEwCLAAAuAAQKfxsAAw4ACAlJIyYqADUCAA4ACAnKIiYqADUCAA8AAQkSHZknAEEAAAAA.Devona:BAABLgAECn8eAAMHAAgJuh2lJQC0AQAHAAcJtBylJQC0AQANAAcJjBDLeABcAQAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingledangle:BAABLgAECn8iAAIQAAgJlBT2DACyAQAQAAgJlBT2DACyAQAAAA==.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJFQARAAwiAA==.Dragooncrush:BAAALgADCgcJCwAAAA==.Dragoonnick:BAACLgAFFH8LAAISAAQJcxKzAwBOAQASAAQJcxKzAwBOAQAuAAQKfz0AAhIACQnSGxYEAHQCABIACQnSGxYEAHQCAAAA.Drazzy:BAAALgAECgIJAgAAAA==.',
Eg='Egg:BAAALgAFFAEJAQABLgAFFAYJFwATAKcTAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAABLgAECn8oAAIMAAkJLBIQPgDLAQAMAAkJLBIQPgDLAQAAAA==.',
Ey='Eyekicku:BAABLgAECn8cAAIUAAgJdSBEDABZAgAUAAgJdSBEDABZAgAAAA==.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgUJCAAAAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.Fuyuhex:BAAALgAFFAIJAwAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gi='Gibbousbogg:BAAALgADCgEJAQAAAA==.',
Gr='Graycieden:BAAALgAECgYJCQAAAA==.',
Gu='Guldangit:BAACLgAFFH8iAAMMAAgJWxy2AQAmAgAMAAgJNBy2AQAmAgAVAAUJ1Ry7AQBnAQAuAAQKfzIABBUACQn/JUYAAFADABUACQkSJUYAAFADAAwACQkBI2oIAD4DABYABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgUJBgAAAA==.',
He='Hellspawn:BAABLgAECn9FAAIXAAkJyg/UFQCkAQAXAAkJyg/UFQCkAQAAAA==.',
Hh='Hhounow:BAAALgADCgcJDAAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECgcJDQAAAA==.Holygrim:BAACLgAFFH8fAAIYAAgJeyMbAAApAwAYAAgJeyMbAAApAwAuAAQKfx0AAxgACAljJuABAFcDABgACAljJuABAFcDABkAAQk+Cb9zAC4AAAAA.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn9FAAQaAAkJPx9ZBQASAwAaAAkJPx9ZBQASAwAZAAcJ0RmOGgDLAQAYAAQJrQuVXQC8AAAAAA==.Howii:BAABLgAECn9HAAIbAAkJnSXqAABPAwAbAAkJnSXqAABPAwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8bAAIGAAcJ+BLaYQBUAQAGAAcJ+BLaYQBUAQAAAA==.',
Je='Jeraziah:BAAALgAECgUJEQABLgAECgkJNAACAKggAA==.',
Jo='Johnnyjr:BAABLgAECn8kAAIFAAkJASHlBAD5AgAFAAkJASHlBAD5AgAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
La='Laggers:BAABLgAECn8jAAIcAAgJdxaqFgBdAQAcAAgJdxaqFgBdAQAAAA==.',
Li='Litbit:BAABLgAECn8fAAIEAAgJ1wO1qwAOAQAEAAgJ1wO1qwAOAQAAAA==.Litbitonme:BAAALgAECgQJCgAAAA==.Litllit:BAAALgAECgMJAwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8fAAIOAAgJax9eJgBHAgAOAAgJax9eJgBHAgAAAA==.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8dAAIEAAcJTBERfABjAQAEAAcJTBERfABjAQAAAA==.',
Me='Megahottie:BAAALgAECgEJAQAAAA==.',
Mi='Mirant:BAAALgAECgUJDwAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
['Mâ']='Mâchine:BAAALgAFFAIJAgABLgAFFAUJFQAOAMgWAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
Of='Of:BAAALgAECgEJAgAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8dAAMXAAkJWxugEQBRAgAXAAkJWxugEQBRAgATAAQJ6gTkyQBkAAAAAA==.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJRQAaAD8fAA==.',
Pe='Periodic:BAACLgAFFH8OAAICAAQJKCNPEQCRAQACAAQJKCNPEQCRAQAuAAQKfy8AAgIACQnkI/QAAJkDAAIACQnkI/QAAJkDAAAA.',
Pl='Platen:BAABLgAECn8dAAIGAAgJzBBWVAB4AQAGAAgJzBBWVAB4AQAAAA==.',
Po='Potter:BAABLgAECn9FAAIEAAkJbB8lFQDAAgAEAAkJbB8lFQDAAgAAAA==.',
Ra='Raffa:BAABLgAECn8jAAIUAAcJiB5JFADxAQAUAAcJiB5JFADxAQAAAA==.Rakandei:BAAALgADCgMJAwAAAA==.Ramaylis:BAAALgADCgEJAQAAAA==.Raptor:BAABLgAFFH8JAAIEAAUJGRxsMQBiAQAEAAUJGRxsMQBiAQAAAA==.Rapunzel:BAAALgAECgkJBgAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8aAAMdAAgJ8AN0NwC1AAAdAAgJqwN0NwC1AAAFAAYJBwOEZwCJAAAAAA==.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8aAAIQAAYJkyC6AADsAQAQAAYJkyC6AADsAQAuAAQKfy0AAhAACQkQJQIBADgDABAACQkQJQIBADgDAAAA.',
Ro='Rovintis:BAABLgAECn82AAIdAAgJpBqjCgAXAgAdAAgJpBqjCgAXAgAAAA==.',
Ry='Rynne:BAABLgAECn8VAAQCAAgJCxSQQAB5AQACAAcJ1hGQQAB5AQAeAAcJ8AcBHAAKAQADAAEJZwPYnAAdAAAAAA==.',
Sa='Sansundertal:BAABLgAECn8wAAIKAAkJsSJ+AgBJAwAKAAkJsSJ+AgBJAwAAAA==.Sargeràs:BAAALgADCgcJDAABLgAECgMJAwABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn8sAAIbAAgJchYhFAChAQAbAAgJchYhFAChAQAAAA==.Sentinäl:BAAALgADCgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8IAAICAAMJ9BBfNwDPAAACAAMJ9BBfNwDPAAAuAAQKfxoAAgIACQkNFds4AJsBAAIACQkNFds4AJsBAAAA.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgUJBgAAAA==.',
Si='Silvertiger:BAABLgAECn9EAAMRAAkJ3h+EBADMAgARAAkJ3h+EBADMAgAfAAcJgg+dPABsAQAAAA==.',
Sl='Slabbydabby:BAAALgAECgYJCgAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgAECgEJAQABLgAECgkJRQAaAD8fAA==.Sneaki:BAABLgAECn9DAAQgAAkJdyXNAwDrAgAgAAkJ+SPNAwDrAgAhAAgJ/Ry5AwA0AgASAAEJsSMdGgBpAAAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQYAAYJbRfiLACTAQAYAAYJbRfiLACTAQAZAAQJ5gMhTQChAAAaAAIJkQhZTQBdAAAAAA==.',
So='Sorynia:BAABLgAECn8YAAIGAAgJnwY1bwA0AQAGAAgJnwY1bwA0AQAAAA==.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8LAAITAAMJ5xkFRQDrAAATAAMJ5xkFRQDrAAAuAAQKfxsAAhMACAmNIZolABkCABMACAmNIZolABkCAAAA.Startawar:BAACLgAFFH8FAAINAAIJxhIMagCbAAANAAIJxhIMagCbAAAuAAQKfyQAAg0ACAnHIywWAOQCAA0ACAnHIywWAOQCAAAA.Stormbeard:BAAALgAECgUJBQABLgAFFAYJFwANANwiAA==.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAFFAEJAQAAAA==.',
['Sø']='Sømebody:BAAALgAECgMJAwAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIFAAcJjRj6LwDvAQAFAAcJjRj6LwDvAQAAAA==.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAABLgAECn8uAAMiAAkJYyM2AgCbAwAiAAkJYyM2AgCbAwAjAAEJgh4aZQBXAAAAAA==.',
Va='Valerïan:BAAALgADCgEJAQABLgAECgcJEgABAAAAAA==.Vauntmonk:BAAALgADCgMJAwABLgAFFAQJEQAkAFYhAA==.',
Ve='Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAACLgAFFH8GAAIOAAMJABmyaAD5AAAOAAMJABmyaAD5AAAuAAQKfy0AAg4ACQk8HlQRAMMCAA4ACQk8HlQRAMMCAAAA.Vishlock:BAABLgAECn8xAAMVAAkJhBkhBQAJAgAVAAkJhBkhBQAJAgAMAAgJ8w4OlAAwAQAAAA==.',
Vo='Voddie:BAABLgAECn8aAAIDAAgJpAwDNgAxAQADAAgJpAwDNgAxAQAAAA==.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAAALgAECgcJDQABLgAECgkJHQAIAEkUAA==.Wapta:BAAALgAFFAEJAQABLgAFFAUJCQAEABkcAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8cAAIlAAgJOxALJABsAQAlAAgJOxALJABsAQABLgAFFAMJBAABAAAAAA==.Woof:BAAALgAECgIJAgAAAA==.',
Xy='Xynelle:BAAALgADCgcJCwAAAA==.',
Ya='Yahtzee:BAAALgAECgQJBwAAAA==.',
Yo='Youdidwhat:BAAALgADCgkJCQAAAA==.',
Za='Zaia:BAAALgAECgcJEwAAAA==.',
Ze='Zenithmage:BAAALgAECgcJDQAAAA==.',
['Ár']='Ártémes:BAAALgADCggJAgAAAA==.',
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
