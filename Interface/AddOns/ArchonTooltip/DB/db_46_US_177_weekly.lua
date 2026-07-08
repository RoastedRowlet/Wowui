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

local lookup = {'Shaman-Restoration','DeathKnight-Unholy','Mage-Frost','Warrior-Fury','Druid-Balance','DeathKnight-Blood','DeathKnight-Frost','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Unknown-Unknown','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Warrior-Arms','Priest-Holy','Hunter-Marksmanship','Monk-Brewmaster','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','Monk-Mistweaver','Druid-Guardian','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Priest-Discipline','Warlock-Affliction','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Shaman-Enhancement','Mage-Fire','DemonHunter-Vengeance',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abelas:BAAALgAECgYJCwAAAA==.Abracadavr:BAAALgAECgIJAgAAAA==.Abracadaxis:BAAALgADCggJCAAAAA==.',
Ad='Adallyn:BAAALgADCgYJCgAAAA==.Adzen:BAAALgAECgQJBQAAAA==.Adêrna:BAABLgAECn85AAIBAAkJSB8tCwAFAwABAAkJSB8tCwAFAwAAAA==.',
Af='Affliction:BAAALgADCgUJBQAAAA==.Aftermathz:BAAALgAECgMJAQAAAA==.',
Ag='Agba:BAABLgAFFH8PAAICAAQJRwaDiQD3AAACAAQJRwaDiQD3AAAAAA==.',
Ah='Ahktari:BAAALgADCgcJBwAAAA==.',
Al='Alaidan:BAAALgAECgkJDQAAAA==.Alanus:BAABLgAECn8rAAIDAAkJMBE5XADJAQADAAkJMBE5XADJAQAAAA==.Alarion:BAAALgAECgQJBwAAAA==.Alavia:BAABLgAECn8/AAIEAAkJfxg+GgAcAgAEAAkJfxg+GgAcAgAAAA==.Alderon:BAAALgADCgYJBgAAAA==.Alinäs:BAABLgAECn8hAAIDAAkJHQ/lYwC2AQADAAkJHQ/lYwC2AQAAAA==.Aliën:BAAALgADCgcJCQAAAA==.Alliumoo:BAABLgAECn8XAAIFAAYJwQkBRwASAQAFAAYJwQkBRwASAQAAAA==.Altana:BAABLgAECn8ZAAMGAAkJThN1HQBsAQAGAAkJNRB1HQBsAQAHAAMJSRXrIADGAAABLgAFFAMJBwAIAO4UAA==.Alydrus:BAACLgAFFH8FAAIDAAIJ1AY4qwB/AAADAAIJ1AY4qwB/AAAuAAQKfz0AAgMACQl/FyoHAIoBAAMACQl/FyoHAIoBAAAA.Alíen:BAAALgAECgQJBAAAAA==.',
Am='Amnesian:BAAALgAECgkJAgAAAA==.',
An='Anberlinean:BAABLgAECn8WAAIJAAYJ5geytAAbAQAJAAYJ5geytAAbAQAAAA==.Angryelf:BAAALgAECgEJAQAAAA==.Angzhixing:BAAALgADCgIJAgAAAA==.Ankles:BAEALgADCgcJBwABLgAFFAQJDgAKAB8RAA==.Annahe:BAABLgAECn8YAAILAAkJjxs+EwAkAgALAAkJjxs+EwAkAgAAAA==.Annale:BAAALgAECgQJBQABLgAECgkJGAALAI8bAA==.Annatara:BAAALgAECgQJCQAAAA==.Anran:BAAALgADCgEJAQAAAA==.Anub:BAAALgADCgYJBgAAAA==.Anzala:BAAALgAECgYJDAAAAA==.',
Ao='Aoba:BAAALgAECgYJCwAAAA==.',
Ar='Areliss:BAAALgAECgUJBQAAAA==.Armsmaster:BAABLgAECn80AAICAAgJmiAqNQAqAgACAAgJmiAqNQAqAgAAAA==.Artemistha:BAAALgAECgQJCgAAAA==.',
As='Asalynn:BAAALgADCgEJAQAAAA==.Asché:BAAALgAECgEJAgAAAA==.',
Av='Avalina:BAAALgAECgEJAQAAAA==.Avengharambe:BAAALgADCgcJBwAAAA==.Averan:BAAALgAECgYJEQAAAA==.Averybug:BAAALgAECgkJAQAAAA==.',
Az='Azarke:BAAALgAECgEJAgAAAA==.',
Ba='Backbeamz:BAAALgAECgYJCQAAAA==.Backspace:BAAALgADCgYJBgAAAA==.Badgër:BAAALgADCgEJAQAAAA==.Baey:BAAALgADCgMJAwABLgAECgkJOgADAMIeAA==.Balduun:BAAALgAECgEJAwAAAA==.Barelycastin:BAABLgAECn8XAAIBAAcJHBesBQB9AQABAAcJHBesBQB9AQAAAA==.Bashdadargon:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Bashoomba:BAAALgAECgQJBQAAAA==.',
Be='Bear:BAABLgAECn8gAAINAAgJVSDBGQCLAgANAAgJVSDBGQCLAgAAAA==.Bearnaked:BAAALgADCgIJAgAAAA==.Bebebluz:BAAALgAECgYJCwAAAA==.Beets:BAAALgAECgEJAQAAAA==.Belgarathh:BAAALgAFFAIJAgAAAA==.Bellíon:BAAALgAECgcJEgAAAA==.Beryline:BAAALgADCgEJAQAAAA==.',
Bi='Bird:BAAALgADCgEJAQAAAA==.Bison:BAAALgAECgMJAwABLgADCgEJAQAMAAAAAA==.Bixee:BAAALgAECgUJCQAAAA==.',
Bl='Blacat:BAABLgAECn84AAMOAAkJCSLrAQAWAwAOAAkJCSLrAQAWAwAFAAIJUAM/eABEAAAAAA==.Bleen:BAAALgAECgUJDAAAAA==.Blitzcomets:BAAALgAECgEJAwAAAA==.Bloodbenders:BAAALgADCgEJAQAAAA==.Blueday:BAAALgAECgUJBQAAAA==.',
Bo='Boagries:BAAALgADCgIJAgAAAA==.Bogeyman:BAABLgAECn81AAIPAAkJrSBsAwDeAgAPAAkJrSBsAwDeAgAAAA==.Boondoks:BAABLgAECn8gAAIKAAcJTh0XIAADAgAKAAcJTh0XIAADAgABLgAECgkJQgABAEYfAA==.Borda:BAAALgAECggJCAAAAA==.Bowrider:BAAALgAECgYJBwAAAA==.',
Br='Breer:BAAALgAECgEJAQAAAA==.Brondeadeye:BAAALgAECgUJBwAAAA==.Brunore:BAAALgAECgYJDAAAAA==.Brìan:BAAALgAECgYJEQAAAA==.',
Bu='Bubbajüdd:BAAALgADCgEJAQAAAA==.',
Ca='Caidi:BAAALgADCgMJAwAAAA==.Caledur:BAAALgAECgYJDAAAAA==.Caliandra:BAAALgAECgEJAQAAAA==.Caratdeullie:BAAALgAECggJCQAAAA==.Careblair:BAAALgADCgkJCQAAAA==.',
Ch='Chakrah:BAABLgAECn8YAAIQAAcJ/gnZNQA9AQAQAAcJ/gnZNQA9AQAAAA==.Challan:BAABLgAFFH8GAAIRAAMJtALNdwCSAAARAAMJtALNdwCSAAAAAA==.Chloe:BAABLgAECn8XAAISAAkJ9AHJ1wAtAAASAAkJ9AHJ1wAtAAAAAA==.Chrno:BAABLgAECn8YAAISAAgJ5xEUNQDHAQASAAgJ5xEUNQDHAQAAAA==.Chunkymonkey:BAAALgADCgYJBgABLgAFFAQJFgADAHwLAA==.',
Ci='Cirilá:BAAALgAECgMJAQAAAA==.',
Cl='Cleric:BAAALgAECgYJBwAAAA==.Clutcha:BAABLgAECn8cAAITAAYJKh3QKgBCAQATAAYJKh3QKgBCAQAAAA==.Clutchcross:BAAALgAECgQJBgABLgAECgYJHAATACodAA==.Clutchplate:BAABLgAECn8jAAMUAAgJKxTLFgCNAQAUAAgJKxTLFgCNAQAVAAEJWgZyhgAjAAAAAA==.Clûtch:BAACLgAFFH8fAAICAAUJISF+HwAjAQACAAUJISF+HwAjAQAuAAQKfyIAAgIACQliH+42AFsCAAIACQliH+42AFsCAAAA.',
Co='Codenameblue:BAAALgADCgEJAQAAAA==.Coldphoenix:BAAALgADCgkJCgAAAA==.Coog:BAAALgADCgEJAQAAAA==.Corynthe:BAABLgAECn9VAAIWAAkJLiQoAACYAwAWAAkJLiQoAACYAwAAAA==.',
Cr='Crickie:BAAALgAECggJEQAAAA==.Crovaxis:BAABLgAECn8qAAMXAAkJlSEzCAD8AQAXAAgJ9yEzCAD8AQANAAIJ/BPr4ACMAAAAAA==.',
Cu='Cursecackler:BAAALgADCgYJBgAAAA==.',
Cy='Cynda:BAAALgADCgMJAwAAAA==.Cyndestine:BAAALgADCgYJBgAAAA==.Cyzarius:BAAALgAECgEJAQAAAA==.',
Da='Daddychill:BAABLgAECn8lAAIYAAkJcBTqFgDyAQAYAAkJcBTqFgDyAQAAAA==.Dahunt:BAAALgAECgcJAQAAAA==.Damekka:BAAALgAECgQJBQAAAA==.Danazer:BAAALgAECgYJBgAAAA==.Danoe:BAAALgAECgIJAgAAAA==.Darktalyn:BAABLgAECn8xAAMWAAkJgBRdGwDuAQAWAAgJFhZdGwDuAQAQAAgJ2Q9jQAAOAQAAAA==.Davidaire:BAAALgAECgEJAQAAAA==.',
De='Deadpaws:BAAALgADCgMJAwAAAA==.Deathbinger:BAAALgADCgEJAQAAAA==.Deathgriped:BAABLgAECn84AAIGAAgJmBheEwDbAQAGAAgJmBheEwDbAQAAAA==.Deathhawkzz:BAACLgAFFH8TAAMZAAQJRgqLEgCjAAAaAAQJRgoSYQAFAQAZAAMJLgOLEgCjAAAuAAQKfxoAAxkACAmcFOYLAAQCABkABwn6FeYLAAQCABoABAntEYSmAPQAAAAA.Deathphoenix:BAAALgADCgcJBwAAAA==.Deathslock:BAAALgADCgQJBAAAAA==.Deekura:BAABLgAECn9PAAMCAAgJIRQvBQCqAQACAAgJIRQvBQCqAQAHAAIJlQHbOgAyAAAAAA==.Deladorana:BAAALgADCgUJBQAAAA==.Delimira:BAAALgAECgQJCAAAAA==.Dellma:BAAALgADCgYJDAAAAA==.Delusion:BAAALgAECgYJEgAAAA==.Demonpapi:BAABLgAFFH8GAAIaAAMJ6AJ1kACjAAAaAAMJ6AJ1kACjAAAAAA==.Demoryx:BAEALgAECgQJBAABLgAECgkJJAAbAPwbAA==.Denjack:BAAALgAECgcJEAAAAA==.Dewayne:BAAALgAECgUJBQAAAA==.',
Dh='Dhadzen:BAAALgAECgQJCwAAAA==.',
Di='Dinak:BAAALgAECgUJBQAAAA==.Diodotus:BAAALgADCgEJAQAAAA==.Dionan:BAABLgAECn8sAAIJAAkJZRKzXwCyAQAJAAkJZRKzXwCyAQAAAA==.Dirtysouth:BAABLgAFFH8FAAITAAMJTwxMEADOAAATAAMJTwxMEADOAAABLgAFFAUJGwANADAhAA==.',
Do='Docs:BAABLgAECn8vAAIKAAgJbhmtFwBLAgAKAAgJbhmtFwBLAgAAAA==.Doks:BAABLgAECn9CAAIBAAkJRh9yDQDrAgABAAkJRh9yDQDrAgAAAA==.Dontpanic:BAEBLgAECn8oAAIcAAcJZh3KAwDHAQAcAAcJZh3KAwDHAQABLgAFFAQJDgAKAB8RAA==.Doomsnake:BAAALgADCgMJAwABLgADCgEJAQAMAAAAAA==.Dove:BAAALgADCgYJBgAAAA==.',
Dr='Dragana:BAAALgAECgIJAgAAAA==.Dragomalfoy:BAAALgADCgQJBAAAAA==.Dragondznuts:BAAALgAFFAQJBAAAAA==.Dragõn:BAAALgAECgYJEgAAAA==.Drexeos:BAAALgADCgcJBwAAAA==.Drinker:BAAALgADCgUJBQAAAA==.Drunkenhealz:BAAALgAECgkJBQAAAA==.',
Du='Dunir:BAAALgAECgcJDQAAAA==.',
Ea='Ealara:BAABLgAECn8eAAINAAgJ7gl6dQBUAQANAAgJ7gl6dQBUAQAAAA==.',
Ed='Edran:BAAALgADCgcJFQAAAA==.',
Ei='Eifel:BAAALgAECgQJBAABLgAECgkJGwAJABceAA==.Eimin:BAAALgADCgYJCgAAAA==.',
El='Eldarion:BAAALgAECgMJAgAAAA==.Elfmonk:BAAALgAECgEJAQAAAA==.Ellipses:BAAALgAECgMJAwABLgAECggJLwAGACsZAA==.',
Em='Emeraldz:BAABLgAECn8mAAILAAgJcRwbFAAaAgALAAgJcRwbFAAaAgAAAA==.',
En='Eneru:BAAALgADCgYJCAABLgAECggJHwAKAJ0XAA==.',
Er='Erebrethil:BAAALgAECgYJDwABLgAECggJMgAcANkaAA==.',
Es='Espe:BAABLgAECn8cAAIYAAkJyhM7GwDLAQAYAAkJyhM7GwDLAQAAAA==.',
Eu='Eucalyptia:BAAALgADCgQJBAAAAA==.Euli:BAABLgAFFH8FAAIdAAQJRg2lCQC/AAAdAAQJRg2lCQC/AAABLgAFFAgJGwAYAJ8fAA==.',
Ev='Evenin:BAAALgADCgIJAgAAAA==.',
Ex='Exoncantotem:BAAALgADCgQJBAAAAA==.',
Fa='Faenor:BAAALgAECgUJDQAAAA==.Fallen:BAABLgAECn8UAAIFAAkJDBWpAQD+AQAFAAkJDBWpAQD+AQAAAA==.Faynor:BAABLgAECn9EAAMYAAkJeBiZAQCgAQAYAAkJeBiZAQCgAQALAAYJbROzNQAsAQAAAA==.Faynór:BAABLgAECn8VAAIGAAgJSQu1AwApAQAGAAgJSQu1AwApAQABLgAECgkJRAAYAHgYAA==.',
Fe='Feloni:BAAALgAECgMJAwAAAA==.',
Fi='Finalone:BAAALgAECgEJAQAAAA==.Firêfly:BAABLgAECn8WAAIJAAkJ8QhlqAAqAQAJAAkJ8QhlqAAqAQAAAA==.',
Fk='Fknsteve:BAAALgADCgYJBgAAAA==.',
Fl='Flaptix:BAAALgAECgMJAwAAAA==.Flipingflerp:BAAALgAECgcJEQAAAA==.Flloran:BAAALgAECgYJDAAAAA==.Floragoth:BAAALgAECgEJAQAAAA==.Flowers:BAAALgADCgkJCQAAAA==.Fluffboi:BAABLgAECn81AAILAAkJbwpMLwBMAQALAAkJbwpMLwBMAQAAAA==.',
Fo='Fourloko:BAAALgAECgEJAQAAAA==.Foxyblue:BAABLgAECn8UAAIWAAYJTBV3NABtAQAWAAYJTBV3NABtAQAAAA==.',
Fr='Fraggle:BAECLgAFFH8OAAMKAAQJHxH5KQDXAAAKAAQJHxH5KQDXAAAJAAMJUwk7eQDDAAAuAAQKfycAAwoACAl+IBsLAMcCAAoACAl+IBsLAMcCAAkABAmtEELWAOsAAAAA.Freefromfate:BAAALgAECgEJAQAAAA==.Frogchi:BAAALgAECgcJDgAAAA==.Frostbité:BAABLgAECn83AAIPAAkJ0B/QAwDPAgAPAAkJ0B/QAwDPAgAAAA==.Fruit:BAABLgAECn8cAAIZAAcJFBJLFwDpAAAZAAcJFBJLFwDpAAAAAA==.',
Fu='Fuknak:BAAALgAECgIJAwAAAA==.Fumikiko:BAAALgADCgIJAgABLgAFFAMJBwAIAO4UAA==.Fumus:BAAALgAFFAEJAQAAAA==.Furrykarg:BAAALgAECgEJAQABLgAECgQJBgAMAAAAAA==.',
['Fà']='Fàynor:BAAALgAECggJEgABLgAECgkJRAAYAHgYAA==.',
['Fí']='Físh:BAAALgADCgYJBgABLgAFFAMJBwAIAO4UAA==.',
['Fú']='Fúzzy:BAAALgADCgEJAgABLgAFFAEJAQAMAAAAAA==.',
Ga='Gakkle:BAABLgAECn8mAAIEAAkJghsyAgDQAQAEAAkJghsyAgDQAQAAAA==.Galadralvia:BAABLgAECn8eAAIUAAkJRBWmEgDBAQAUAAkJRBWmEgDBAQAAAA==.Gali:BAABLgAECn8ZAAIXAAgJJQX5AgC0AAAXAAgJJQX5AgC0AAAAAA==.Ganaan:BAAALgAECgEJAwAAAA==.Garagas:BAAALgAECgIJAwAAAA==.',
Ge='Gearsofbob:BAAALgAFFAIJBAAAAA==.Gekkle:BAAALgADCgUJBQAAAA==.',
Gh='Ghorn:BAAALgAECgEJAQAAAA==.Ghoulei:BAABLgAECn82AAICAAkJzx+3GgCmAgACAAkJzx+3GgCmAgAAAA==.',
Gi='Girlscout:BAEALgAECgYJBgABLgAFFAQJDgAKAB8RAA==.',
Gl='Glaistiguain:BAAALgAECgYJCwABLgAECggJNAACAJogAA==.Glenheals:BAAALgADCgkJEgAAAA==.Glifin:BAAALgAECgcJDgAAAA==.Gloomstalkin:BAABLgAECn8/AAIeAAkJNhd9DgBDAgAeAAkJNhd9DgBDAgAAAA==.',
Gn='Gnøsis:BAAALgADCggJEQAAAA==.',
Go='Goldìelocks:BAAALgAECgUJCAAAAA==.Gom:BAAALgAECgIJAgAAAA==.Gomdrog:BAAALgAECgEJAQAAAA==.',
Gr='Gr:BAABLgAECn8oAAIfAAgJ7QzADgA4AQAfAAgJ7QzADgA4AQAAAA==.Grannecs:BAAALgADCgEJAQAAAA==.Greenygreen:BAAALgAECgEJAQAAAA==.Grimmli:BAAALgADCgEJAQAAAA==.Grizelda:BAAALgADCgQJBAAAAA==.Grizzledpaw:BAAALgAECgUJDAAAAA==.Gromcresh:BAAALgAECgUJBQAAAA==.Gryffs:BAABLgAECn86AAMUAAkJ3CCdBQC8AgAUAAkJ3CCdBQC8AgAVAAEJ1Aq1gAApAAAAAA==.',
Gu='Guenhwyn:BAAALgADCgEJAQAAAA==.Gum:BAAALgAECgcJBwABLgAECgkJNQAPAK0gAA==.Gutts:BAABLgAECn8nAAQUAAkJDSLdBQC0AgAUAAkJDSLdBQC0AgAVAAcJ3BKtLQATAQAEAAQJ0Q7wfQDFAAAAAA==.',
Ha='Hadron:BAAALgAECgQJCQAAAA==.Hahkoa:BAAALgADCgMJAwAAAA==.Halomea:BAAALgADCgQJBAAAAA==.Hanukira:BAAALgADCgUJBQAAAA==.Happi:BAAALgAECgYJCQABLgAFFAgJKgARAIUiAA==.Happyhour:BAAALgAECgYJBgABLgAFFAgJKgARAIUiAA==.Harald:BAABLgAECn8gAAMCAAkJ9g72qQAdAQACAAkJogz2qQAdAQAGAAIJ4hswPQCbAAAAAA==.Harkle:BAAALgADCgcJDQAAAA==.Haruun:BAAALgAECgIJAgAAAA==.',
He='Healyoself:BAAALgAECggJCQAAAA==.Heliõs:BAAALgAECgEJAQAAAA==.Hesmydaddy:BAABLgAECn9BAAIWAAkJuRBNAwB/AQAWAAkJuRBNAwB/AQAAAA==.',
Ho='Honcho:BAAALgAECgEJAQAAAA==.Honestie:BAAALgAECgQJCgAAAA==.Honêy:BAEALgAFFAIJAQABLgAECgkJJAAbAPwbAA==.Hotdogstand:BAACLgAFFH8XAAITAAgJWyIoCAAlAgATAAgJWyIoCAAlAgAuAAQKfzEABBMACQlwJQcDACADABMACQlwJQcDACADAB8ABAmEIYELAHMBACAAAQkrIq0eAFgAAAAA.',
Hu='Hukan:BAAALgAECgQJBgAAAA==.Huntarius:BAAALgAECgEJAQAAAA==.Huzzaah:BAEALgAFFAEJAQABLgAFFAQJDgAKAB8RAA==.',
Hy='Hyperius:BAAALgADCgIJAgAAAA==.',
['Hö']='Höneÿdew:BAABLgAECn8ZAAINAAgJ9Bg2LAADAgANAAgJ9Bg2LAADAgAAAA==.',
Ic='Icemann:BAAALgAECgEJAgAAAA==.',
Il='Ilidrayssel:BAABLgAECn8aAAIXAAcJbQNHIACuAAAXAAcJbQNHIACuAAAAAA==.Illida:BAAALgAECgMJCQAAAA==.Illidad:BAAALgAECgQJBAAAAA==.Ilyssara:BAAALgAECgIJAQABLgAECggJLwAGACsZAA==.',
Im='Imhappy:BAAALgAECgUJCgABLgAFFAgJKgARAIUiAA==.Imherdaddy:BAAALgAECgcJBwABLgAECgkJPwAeADYXAA==.',
In='Indracus:BAAALgAECgQJCQAAAA==.Innervape:BAAALgADCgMJAwAAAA==.',
Ir='Ironfay:BAAALgAECggJCQABLgAECgkJRAAYAHgYAA==.',
It='Itakemeds:BAAALgAECgUJBQABLgAECgkJUAABANAbAA==.',
Ja='Jacorict:BAABLgAECn8UAAIJAAYJJws90wDuAAAJAAYJJws90wDuAAAAAA==.Jagga:BAAALgADCgMJAwAAAA==.Jarrack:BAABLgAECn89AAIDAAkJrB4tAwBDAgADAAkJrB4tAwBDAgAAAA==.',
Je='Jellyhawk:BAAALgAECgEJAQAAAA==.Jessicae:BAAALgAECggJEgAAAA==.Jeuno:BAAALgAECgYJBwABLgAFFAMJBwAIAO4UAA==.',
Jo='Josephd:BAAALgADCgEJAQABLgAECggJPgAFABwcAA==.Josephedd:BAABLgAECn8+AAIFAAgJHBwYEwA8AgAFAAgJHBwYEwA8AgAAAA==.',
Ju='Judgment:BAAALgAECgEJAQAAAA==.Jukk:BAABLgAECn8oAAIDAAkJEgrkEADzAAADAAkJEgrkEADzAAAAAA==.Junazeena:BAABLgAECn88AAMbAAkJSgx/BABGAQAbAAkJSgx/BABGAQABAAIJCgKU0gA4AAAAAA==.',
Jy='Jygglypuff:BAAALgAECgUJBQAAAA==.',
Ka='Kaji:BAABLgAECn8jAAIcAAYJSROmRQBVAQAcAAYJSROmRQBVAQAAAA==.Kalistus:BAAALgAECgYJBwAAAA==.Kargfu:BAAALgAECgQJBgAAAA==.Karolat:BAAALgAECgUJBgAAAA==.Kayfabe:BAABLgAECn8bAAIDAAkJ3QNz+gAGAQADAAkJ3QNz+gAGAQAAAA==.Kayfay:BAAALgAECgMJAwAAAA==.Kazz:BAAALgAFFAEJAQAAAA==.',
Ke='Keishilda:BAABLgAECn8bAAMhAAYJ1Ah1UwCzAAAhAAYJ1Ah1UwCzAAAQAAUJOgQzbABuAAAAAA==.Keladria:BAAALgAECgQJBwAAAA==.Kelirra:BAAALgADCgQJCAAAAA==.Kelvyren:BAAALgADCgEJAQAAAA==.Kenel:BAABLgAECn83AAMSAAkJhBcpGgB0AgASAAkJhBcpGgB0AgAFAAUJcRH5UADKAAAAAA==.Kerea:BAABLgAECn9NAAMSAAkJngtUBABbAQASAAkJngtUBABbAQAFAAMJAQsJZwCCAAAAAA==.Kerob:BAAALgAECgMJBgAAAA==.Keyarga:BAAALgADCgIJAgABLgAECgcJFgAeAM4TAA==.',
Kh='Khazargon:BAAALgAECgQJCgAAAA==.',
Ki='Kicken:BAABLgAECn9WAAQaAAkJBR1kFgCeAgAaAAgJRBtkFgCeAgAZAAMJihkmPwC4AAAiAAEJxB/sCABUAAAAAA==.Kitschy:BAAALgADCgEJAQAAAA==.Kittyperry:BAAALgAECgQJBAAAAA==.Kizmo:BAAALgAECgEJAQAAAA==.',
Kn='Knome:BAABLgAECn86AAIDAAkJwh4PHQCuAgADAAkJwh4PHQCuAgAAAA==.',
Ko='Koana:BAAALgAECgkJCwAAAA==.Kororin:BAAALgAECgMJAwAAAA==.Korthelan:BAABLgAECn88AAIRAAkJLhJaPADWAQARAAkJLhJaPADWAQAAAA==.Kothara:BAABLgAECn9GAAINAAkJ1RmLAgBpAgANAAkJ1RmLAgBpAgAAAA==.Kotongar:BAAALgADCgMJAwAAAA==.',
Kr='Kreeoo:BAAALgAECgIJAgAAAA==.Krimzin:BAACLgAFFH8bAAINAAUJMCGaJABzAQANAAUJMCGaJABzAQAuAAQKfx8AAw0ACAnfIZQhADwCAA0ACAnfIZQhADwCAB4AAgkaEHldAD4AAAAA.Krystine:BAABLgAECn8eAAISAAcJNhXgTwBPAQASAAcJNhXgTwBPAQAAAA==.',
Ks='Kserasera:BAABLgAFFH8PAAIFAAQJ4g+ECwABAQAFAAQJ4g+ECwABAQAAAA==.',
Ku='Kuball:BAAALgAECgYJCgABLgAECgkJJwAUAA0iAA==.Kukuruku:BAABLgAECn8ZAAIbAAkJmwzqPQA9AQAbAAkJmwzqPQA9AQAAAA==.',
['Kì']='Kìssofdeath:BAAALgAECgUJBQAAAA==.',
['Kî']='Kîllara:BAABLgAECn8qAAIBAAkJrhW4KQAWAgABAAkJrhW4KQAWAgAAAA==.',
La='Labialicious:BAAALgAECgEJAgAAAA==.Lanfeår:BAABLgAECn8VAAICAAYJCwjL4ADTAAACAAYJCwjL4ADTAAAAAA==.Lanskies:BAABLgAECn8ZAAICAAkJPRXMMgAzAgACAAkJPRXMMgAzAgAAAA==.',
Le='Leafymeds:BAAALgAECgYJEAABLgAECgkJUAABANAbAA==.Lebronjames:BAABLgAFFH8FAAICAAMJdhpzfwAIAQACAAMJdhpzfwAIAQAAAA==.Leiluna:BAAALgADCgkJEQAAAA==.Letheos:BAABLgAFFH8JAAIGAAMJHBraCgDoAAAGAAMJHBraCgDoAAAAAA==.',
Li='Libertinne:BAABLgAECn8cAAIEAAgJMxewMwB8AQAEAAgJMxewMwB8AQAAAA==.Librarte:BAABLgAECn86AAIJAAkJNw2BbACVAQAJAAkJNw2BbACVAQAAAA==.Ligmanuts:BAAALgAECgIJBAAAAA==.Lija:BAAALgAECgYJBgABLgAECgkJKAADABIKAA==.Lillytrae:BAAALgAECgMJBQAAAA==.Lilmeds:BAABLgAECn8XAAMhAAkJ+QcGLgBqAQAhAAkJxwcGLgBqAQAWAAgJBQRVQADtAAABLgAECgkJUAABANAbAA==.Listie:BAAALgADCgQJBAABLgAECgQJBAAMAAAAAA==.Litty:BAABLgAECn8oAAIDAAcJASX8KwBpAgADAAcJASX8KwBpAgAAAA==.Lizrdkng:BAAALgADCgMJBgAAAA==.',
Lo='Locktärd:BAACLgAFFH8MAAQiAAQJiBsVBgAiAQAiAAQJiBsVBgAiAQAaAAIJShYXMwCtAAAZAAIJogaEDgCXAAAuAAQKfyoABCIACAmIH6oCAJACACIACAk+H6oCAJACABoACAktGRZCAAYCABkAAgkLHIJGAJwAAAAA.Lohken:BAAALgAECgQJCwAAAA==.Loralila:BAAALgAECgUJCQABLgAECgkJHgAUAEQVAA==.Lox:BAABLgAECn9NAAMZAAkJSRqpAAAIAgAZAAkJSRqpAAAIAgAaAAIJFQSeJgFCAAAAAA==.',
Lu='Lucieb:BAAALgAECgEJAQAAAA==.',
Ly='Lydirn:BAABLgAECn8gAAQJAAkJ+RxtQAAFAgAJAAgJ3x1tQAAFAgAKAAQJzRVpVQDiAAAPAAIJoBykMQCfAAAAAA==.Lyofel:BAAALgAECgYJDwAAAA==.Lyonel:BAAALgADCggJCAAAAA==.Lysaviel:BAAALgAECgEJAgAAAA==.',
['Lí']='Lítterbox:BAABLgAFFH8GAAIOAAMJzAmIBAC/AAAOAAMJzAmIBAC/AAAAAA==.',
Ma='Magedzen:BAAALgAECgMJBAAAAA==.Magicguy:BAACLgAFFH8GAAIDAAMJ5Qo0QQB2AAADAAMJ5Qo0QQB2AAAuAAQKfxsAAgMACQlnDzNVAN0BAAMACQlnDzNVAN0BAAAA.Mahariel:BAABLgAECn8wAAINAAkJ/RD2PgDmAQANAAkJ/RD2PgDmAQAAAA==.Mahdy:BAABLgAECn9HAAIJAAkJGR3GJAByAgAJAAkJGR3GJAByAgAAAA==.Mahoe:BAAALgAECgQJBwAAAA==.Maivel:BAAALgAECgcJCAAAAA==.Malva:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Manandaar:BAAALgAECgIJBAAAAA==.Mandret:BAAALgAECgMJBAABLgAFFAIJBQAKAD8UAA==.Manicppanic:BAEBLgAECn8gAAITAAgJxxVrHQCrAQATAAgJxxVrHQCrAQABLgAFFAQJDgAKAB8RAA==.Manrypurp:BAAALgAECgUJDQAAAA==.Marcie:BAABLgAECn9SAAIFAAkJ+BNnAgCwAQAFAAkJ+BNnAgCwAQAAAA==.Martinriggz:BAAALgAECgMJBgAAAA==.',
Mc='Mchammer:BAAALgAECgEJAgAAAA==.',
Me='Meatyloaf:BAABLgAECn8gAAIHAAkJfwbiHgDVAAAHAAkJfwbiHgDVAAAAAA==.Melkedrik:BAABLgAECn8aAAIjAAkJ4g2TJABTAQAjAAkJ4g2TJABTAQAAAA==.Melleren:BAAALgAECgYJCQAAAA==.Messande:BAAALgAECgUJBgAAAA==.',
Mi='Minõs:BAAALgADCgkJEAAAAA==.Mirai:BAAALgADCgUJBQAAAA==.Mirei:BAABLgAECn9WAAIWAAkJHxD2AwBcAQAWAAkJHxD2AwBcAQAAAA==.Mistdancer:BAAALgADCgYJBgABLgAFFAIJCgAHAI0GAA==.Mitsurugi:BAAALgAECgEJAgABLgAFFAIJCgAHAI0GAA==.Miyagí:BAAALgAECgcJDgABLgAECggJGAAGAKYdAA==.',
Mo='Mochisama:BAAALgAECgYJCAAAAA==.Mojam:BAAALgAECgQJEAAAAA==.Monk:BAAALgAECgEJAQAAAA==.Monkadzen:BAAALgAECgEJBAAAAA==.Moonless:BAAALgAECgEJAgAAAA==.Moovidlin:BAABLgAECn8XAAIEAAkJBQteNQBzAQAEAAkJBQteNQBzAQABLgAECgkJKAADABIKAA==.Mordian:BAAALgAECgYJBgAAAA==.Morinnas:BAAALgAECgQJBQAAAA==.Moschpit:BAAALgADCgEJAQAAAA==.',
Mu='Munkeez:BAAALgADCgMJAwAAAA==.Murdermoo:BAAALgADCgMJAwAAAA==.Murkessa:BAAALgAECgQJBwAAAA==.Mushhead:BAAALgAECgUJCAAAAA==.Mustepin:BAAALgAECgQJBAABLgAFFAQJDwAEAEobAA==.',
My='Myishaa:BAAALgADCgIJAgAAAA==.Mykeal:BAAALgADCgMJBQAAAA==.Myndigo:BAAALgAECgEJAQAAAA==.Mystryl:BAAALgADCgkJEQAAAA==.Mythantherox:BAABLgAFFH8HAAIVAAMJrR1YHAAJAQAVAAMJrR1YHAAJAQABLgAFFAYJFAAkAGgWAA==.',
['Mì']='Mìstra:BAAALgADCgUJBwAAAA==.',
Na='Nanlaria:BAAALgAECgEJAwAAAA==.Nargo:BAAALgADCgYJCgAAAA==.Nataliia:BAAALgAECgQJBAAAAA==.',
Ne='Necrostalker:BAAALgADCgkJCQABLgADCgEJAQAMAAAAAA==.Negative:BAAALgAECgQJCgAAAA==.Neltherius:BAAALgAECgEJAQAAAA==.Nerwende:BAAALgAECgEJAQAAAA==.Nethershade:BAABLgAECn9KAAIfAAkJ1SEoAAC8AgAfAAkJ1SEoAAC8AgAAAA==.Netherstörm:BAAALgAECgcJCgAAAA==.Nezot:BAAALgAECgEJAQABLgAECgkJHAACACERAA==.',
Ni='Niclea:BAAALgAECgQJBAAAAA==.Nightelm:BAACLgAFFH8HAAQIAAMJ7hQ/QgC+AAAIAAMJ7hQ/QgC+AAAkAAEJnBKoDQBIAAAlAAEJZgQCMAAmAAAuAAQKfysABAgACQltHw8LAKgCAAgACQlnHw8LAKgCACUABgleDBY0AM0AACQABAn3G3UZAIkAAAAA.Ninym:BAAALgAECgEJAQAAAA==.Niënor:BAABLgAECn8yAAIcAAgJ2RokAwDkAQAcAAgJ2RokAwDkAQAAAA==.',
Nj='Njorvir:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.',
No='Noslien:BAAALgAECgUJBwAAAA==.Nostradamuz:BAAALgAECgEJAQAAAA==.Novasong:BAAALgAECgEJAwAAAA==.',
Ny='Nymneria:BAABLgAECn8WAAIZAAgJBAuDFgDyAAAZAAgJBAuDFgDyAAAAAA==.Nyxstonia:BAACLgAFFH8eAAIUAAQJxhicBwD7AAAUAAQJxhicBwD7AAAuAAQKf0AAAhQACQkNH3sIAHICABQACQkNH3sIAHICAAAA.',
Ob='Oballi:BAAALgAECgUJBwAAAA==.',
Od='Oddsaint:BAAALgAECgEJAwAAAA==.',
Ol='Olierra:BAAALgAECgYJDAAAAA==.',
On='Onlyvoids:BAAALgAECgMJAwAAAA==.',
Or='Orhan:BAAALgAECgQJBAABLgAECgkJRAAYAHgYAA==.Ornac:BAAALgADCgcJEAAAAA==.',
Ot='Otkspring:BAACLgAFFH8HAAMEAAMJHwonPQC5AAAEAAMJZggnPQC5AAAVAAEJPwecQwBAAAAuAAQKfxkAAgQABwmAF/ktAJkBAAQABwmAF/ktAJkBAAAA.Otto:BAABLgAECn8pAAIJAAkJ2hHLXwCxAQAJAAkJ2hHLXwCxAQAAAA==.Ottomagus:BAABLgAECn8fAAIDAAkJAxXjBADTAQADAAkJAxXjBADTAQAAAA==.',
Ox='Oxadin:BAAALgAECgEJAQAAAA==.Oxideous:BAAALgADCgMJAwAAAA==.',
Pa='Paleale:BAABLgAECn8VAAIbAAYJ7wztXQDLAAAbAAYJ7wztXQDLAAAAAA==.Pallyshore:BAAALgADCgMJAwAAAA==.Pallywack:BAAALgAECggJCAAAAA==.Pampoovy:BAEALgADCgMJAwABLgAECgkJFgAeAA4ZAA==.Pandapunk:BAAALgAECggJDgAAAA==.Panic:BAAALgAECgEJAgAAAA==.Pantoponrose:BAAALgAECgYJEQAAAA==.Pastorbash:BAAALgADCggJCQAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Persephoneia:BAABLgAECn8mAAIQAAkJYxF0IgC0AQAQAAkJYxF0IgC0AQAAAA==.',
Pi='Pitnick:BAAALgAECgIJAgAAAA==.',
Pk='Pkashmuk:BAAALgADCgcJBwAAAA==.',
Pr='Prophettool:BAABLgAECn8oAAMJAAkJlAsIgwBpAQAJAAkJlAsIgwBpAQAKAAQJigQEfQCGAAAAAA==.Pruned:BAAALgADCgcJBwABLgAFFAQJDAAiAIgbAA==.',
Pu='Punjistake:BAAALgAECgYJBgAAAA==.',
['Pï']='Pïzzasteve:BAAALgAECgIJAgABLgAFFAEJAQAMAAAAAA==.',
Qu='Quanchii:BAAALgADCgMJAwAAAA==.Quna:BAAALgADCgQJBAAAAA==.',
Ra='Raemie:BAAALgAECgQJCgAAAA==.Ragequit:BAABLgAECn8WAAIUAAgJwhfEFACmAQAUAAgJwhfEFACmAQABLgAECggJLwAGACsZAA==.Raikoho:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Rakulm:BAAALgADCgUJCgAAAA==.Ravenloare:BAAALgAECgQJBAAAAA==.Ravenrest:BAEBLgAECn8vAAIQAAgJqx7GEgA8AgAQAAgJqx7GEgA8AgAAAA==.',
Re='Reaverheim:BAABLgAECn8ZAAQUAAYJAx8PFgCWAQAUAAYJYx4PFgCWAQAEAAQJfxcqZQAeAQAVAAIJBR0lSgCkAAAAAA==.Rehab:BAAALgAFFAEJAQABLgAECggJLwAGACsZAA==.Reiko:BAAALgADCgkJIQABLgAECgkJVgAWAB8QAA==.Remuz:BAAALgAECgUJCwAAAA==.Rennwick:BAAALgAECgQJBgAAAA==.Renriss:BAAALgAECgcJCQABLgAECggJOAAGAJgYAA==.Rey:BAAALgAECggJCgAAAA==.',
Rh='Rhe:BAAALgAECgIJAgABLgAECggJCgAMAAAAAA==.',
Ri='Rilz:BAABLgAECn8qAAICAAkJ3SDmHQCUAgACAAkJ3SDmHQCUAgAAAA==.',
Ro='Rochambeu:BAAALgADCgEJAQAAAA==.Rockasham:BAAALgAECgQJCgAAAA==.Rockyrogue:BAAALgAECgEJAQAAAA==.Rodgerwabbet:BAAALgAECgQJBAAAAA==.Roiddemon:BAAALgADCgQJBAABLgAECggJKwAaABcUAA==.Roiddrood:BAAALgAECgIJAgABLgAECggJKwAaABcUAA==.Roidlock:BAABLgAECn8rAAIaAAgJFxRoVgCZAQAaAAgJFxRoVgCZAQAAAA==.Roidtank:BAAALgAECgUJDAABLgAECggJKwAaABcUAA==.Rongyi:BAAALgADCgIJAgAAAA==.Rosaline:BAAALgAECgYJDgAAAA==.Rosewood:BAAALgAECgkJCAAAAA==.Rottn:BAABLgAECn8vAAMGAAgJKxksAwBNAQAGAAgJKxksAwBNAQACAAEJrgPgnQEhAAAAAA==.Rottnshot:BAAALgADCgYJBgABLgAECggJLwAGACsZAA==.Rottyn:BAABLgAECn8WAAIPAAgJ5hWQAQC2AQAPAAgJ5hWQAQC2AQABLgAECggJLwAGACsZAA==.',
Ru='Runerion:BAAALgAECgEJBQAAAA==.',
Ry='Ry:BAAALgAECgYJBQABLgAECggJCgAMAAAAAA==.',
['Rà']='Ràìn:BAABLgAECn8WAAIDAAgJAgnuoQA4AQADAAgJAgnuoQA4AQAAAA==.',
Sa='Sacrothoth:BAAALgAECgEJAgAAAA==.Safmen:BAABLgAECn8bAAQUAAYJwQdsNgCeAAAUAAYJjAdsNgCeAAAVAAMJMgXiaQBOAAAEAAEJCAr0ogA9AAAAAA==.Sanikoa:BAAALgAECgQJCgAAAA==.Saraid:BAABLgAECn8vAAQSAAkJ9RgHFwCOAgASAAkJ9RgHFwCOAgAFAAUJVRBnDABwAAAdAAIJvQUOeAAtAAAAAA==.Saravase:BAABLgAECn8XAAIBAAYJMgmyEwB3AAABAAYJMgmyEwB3AAAAAA==.Sardel:BAAALgADCgcJBwAAAA==.Sargeros:BAAALgAECgQJBQAAAA==.Sazem:BAAALgADCgIJAgAAAA==.',
Se='Sedaldra:BAAALgADCgYJCwAAAA==.',
Sh='Shadowi:BAAALgAECgQJBQAAAA==.Shadownights:BAABLgAECn8/AAIQAAkJhhdgAgCvAQAQAAkJhhdgAgCvAQAAAA==.Shadowpope:BAAALgAECgkJBgAAAA==.Shamoneyy:BAAALgADCgUJBQAAAA==.Shazi:BAEBLgAECn8kAAMbAAkJ/BuNEgBbAgAbAAkJ/BuNEgBbAgAmAAEJ8Ao1LAA1AAABLgAECgkJJAAbAPwbAA==.Shiki:BAAALgADCgkJEwABLgAECgkJVgAWAB8QAA==.Shimnar:BAAALgAECggJEwABLgAECggJHAAEADMXAA==.Shinifur:BAAALgADCgUJBgAAAA==.Shinoto:BAABLgAECn8ZAAMDAAYJISAxWgDPAQADAAYJISAxWgDPAQAnAAEJDxXQEgA/AAAAAA==.Shiritá:BAAALgAECgMJAgAAAA==.Shockazam:BAAALgAECgcJEgAAAA==.Shrewby:BAAALgAECgEJAQAAAA==.Shyandra:BAAALgADCgYJBgAAAA==.',
Si='Sieghart:BAAALgAECgEJBAAAAA==.Silverstead:BAAALgAECgYJEgAAAA==.Six:BAAALgAECgUJCwABLgAFFAEJAQAMAAAAAA==.',
Sk='Skylines:BAAALgAECgQJBAAAAA==.',
Sl='Sloptop:BAAALgAECgEJAgAAAA==.',
Sn='Snarkyshaman:BAAALgAECgQJBAABLgAECggJLwAGACsZAA==.Snickersbar:BAAALgADCgUJCAAAAA==.Snowynn:BAAALgAECgYJEQAAAA==.Snöw:BAABLgAECn8pAAIDAAkJGhVhQQAYAgADAAkJGhVhQQAYAgAAAA==.Snöwy:BAAALgAECgQJBAAAAA==.',
So='Sojudevourer:BAAALgAECgEJAQAAAA==.Southpaw:BAAALgAECgMJAwAAAA==.',
Sp='Spooki:BAAALgAECgEJAQAAAA==.Spyro:BAABLgAECn8uAAQIAAkJ1A59GgD2AQAIAAkJ1A59GgD2AQAlAAgJABMsEQC4AQAkAAIJYw5CIwA/AAAAAA==.',
Sr='Sron:BAABLgAECn8qAAINAAkJQx1qPQDrAQANAAkJQx1qPQDrAQAAAA==.',
St='Stabalagmite:BAAALgAECgQJBAABLgAECggJLwAGACsZAA==.Stariah:BAABLgAECn8kAAIDAAgJPgttjQBcAQADAAgJPgttjQBcAQAAAA==.Stawn:BAAALgADCgEJAQAAAA==.Stupid:BAAALgADCgIJAgAAAA==.',
Su='Sumwhiteguy:BAAALgAECgEJAQAAAA==.',
Sw='Sweetbeef:BAAALgAECgIJAgAAAA==.Swooze:BAACLgAFFH8QAAIDAAQJHhd6UgA4AQADAAQJHhd6UgA4AQAuAAQKfzsAAgMACQndHVEcALICAAMACQndHVEcALICAAAA.',
Sy='Sylrythriana:BAABLgAECn8ZAAMTAAcJfwSwNQD/AAATAAcJfwSwNQD/AAAfAAIJCwIIKQAxAAABLgAECgkJHgAUAEQVAA==.Syndar:BAAALgAECgQJBAABLgAECgYJBwAMAAAAAA==.Syndicate:BAAALgAECgcJDQAAAA==.Syrenis:BAAALgADCgkJDwABLgAFFAMJBwAIAO4UAA==.',
['Sù']='Sùnnydk:BAAALgADCgcJBwAAAA==.',
Ta='Tahoe:BAAALgADCgYJBgABLgAFFAYJIgARAJEXAA==.Talwaz:BAAALgADCgkJDgAAAA==.Tankinbur:BAAALgAECgYJDQAAAA==.Tanzri:BAAALgAECgMJAwAAAA==.Tarlyn:BAACLgAFFH8MAAIKAAMJCg2yNACcAAAKAAMJCg2yNACcAAAuAAQKfzQABAoACQkRF24XAE4CAAoACQkRF24XAE4CAAkABglcGoyOAFUBAA8AAQkAANI/AD4AAAAA.Tatslight:BAABLgAECn84AAIPAAgJMR1EAQDhAQAPAAgJMR1EAQDhAQABLgAECggJOAAPADEdAA==.Tatsrage:BAAALgAECgEJAQABLgAECggJOAAPADEdAA==.Tazaral:BAAALgADCgEJAQABLgAECgkJCwAMAAAAAA==.',
Te='Ted:BAEBLgAFFH8MAAMSAAYJxBDYDQDeAAASAAUJ1Q7YDQDeAAAFAAIJzwH9HABFAAABLgAFFAQJDgAKAB8RAA==.Temuadêrna:BAAALgAECgQJBAAAAA==.Teysá:BAAALgADCgEJAQAAAA==.',
Th='Thalasso:BAAALgADCgEJAgAAAA==.Thor:BAAALgAECgYJCAAAAA==.Thyandris:BAAALgADCgYJCwAAAA==.Thánátós:BAAALgAECgQJBwAAAA==.',
Ti='Tichar:BAAALgADCgYJBgAAAA==.Timmthemage:BAAALgAECgUJBwABLgAECgEJAQAMAAAAAQ==.Timthehunter:BAAALgAECgEJAQAAAQ==.Timthepally:BAAALgAECggJDAABLgAECgEJAQAMAAAAAQ==.Tinytex:BAABLgAECn8oAAIYAAkJyw7VIwCMAQAYAAkJyw7VIwCMAQAAAA==.Tisiphoneia:BAAALgAECgQJBgAAAA==.',
To='Toberson:BAAALgAECgEJAQAAAA==.Tom:BAAALgAECgQJBAAAAA==.Toxicbanana:BAABLgAECn8VAAIEAAYJeg+LCQDLAAAEAAYJeg+LCQDLAAAAAA==.',
Tr='Tradarynn:BAABLgAECn8gAAIJAAkJ7hujIACEAgAJAAkJ7hujIACEAgAAAA==.Trayvein:BAAALgADCgUJBQAAAA==.Trekk:BAAALgAECgcJBQAAAA==.Tress:BAABLgAECn8UAAImAAYJLx5YEgCQAQAmAAYJLx5YEgCQAQAAAA==.',
Ts='Tsindre:BAAALgAECgEJAgAAAA==.Tsukong:BAAALgAECgEJAQAAAA==.',
Tu='Tulkar:BAAALgAECgcJCgAAAA==.Turambar:BAAALgAECgEJAQAAAA==.',
Ty='Tyriir:BAAALgADCgQJBgAAAA==.Tyviae:BAAALgAECgIJAgAAAA==.',
Um='Umbravine:BAAALgAECggJCQABLgAECggJLwAGACsZAA==.Umbrax:BAAALgAECgQJBQAAAA==.',
Un='Unholymochi:BAABLgAECn8lAAICAAkJHiAgWwC1AQACAAkJHiAgWwC1AQAAAA==.',
Us='Usdaprime:BAAALgAFFAEJAQAAAA==.',
Uw='Uwuzi:BAAALgADCgQJBAAAAA==.',
Va='Valhalia:BAABLgAECn8UAAMaAAgJ6ReEcgBVAQAaAAYJKBiEcgBVAQAZAAMJbg6pQgCqAAAAAA==.Vanyllapea:BAAALgAECgMJAwAAAA==.Varaelitha:BAAALgAECgMJAwAAAA==.Vashan:BAAALgAECgQJBQAAAA==.Vashni:BAAALgAECgkJDAAAAA==.',
Ve='Velinariae:BAAALgADCgYJEAAAAA==.Vengful:BAABLgAECn83AAMjAAkJZB2IAQAVAgAjAAkJZB2IAQAVAgAoAAIJoBeAJAB7AAAAAA==.',
Vi='Vira:BAAALgAECgIJAgAAAA==.Vivy:BAABLgAECn8fAAQaAAkJNhThLwBNAgAaAAkJzRPhLwBNAgAZAAQJaxSaMwDpAAAiAAIJBhXMJgBWAAAAAA==.',
Vo='Vord:BAAALgAECgIJAgAAAA==.Vorumbrae:BAAALgAECgYJCAAAAA==.',
Vu='Vultus:BAAALgAECgIJAgAAAA==.',
Vy='Vylthyra:BAAALgADCgEJAQABLgAECggJLwAGACsZAA==.Vyrkin:BAAALgAECgEJAQAAAA==.Vyrul:BAAALgAECgQJBAABLgAECgQJBAAMAAAAAA==.',
['Vä']='Väntage:BAAALgADCgEJAQAAAA==.',
Wa='Wagyubeef:BAABLgAECn8kAAIEAAkJghdYIADtAQAEAAkJghdYIADtAQAAAA==.Wali:BAABLgAECn8gAAMaAAgJMRPKXQCFAQAaAAgJMRPKXQCFAQAZAAEJAAB9dgAuAAAAAA==.Warlodzen:BAAALgADCgcJBwAAAA==.Wayne:BAAALgAECgQJBAAAAA==.',
We='Weebey:BAAALgADCgEJAQAAAA==.Wenson:BAABLgAECn8cAAMCAAkJIRHfRwDqAQACAAkJIRHfRwDqAQAGAAkJ2wSHOQCtAAAAAA==.',
Wh='Whatupbruh:BAACLgAFFH8SAAMeAAQJ+RKJBwDtAAAeAAQJbxGJBwDtAAANAAMJRxDRawDMAAAuAAQKfyQABB4ABwkcIh4HAIgCAB4ABwm5IR4HAIgCAA0AAQkJG1EcAUAAABcAAQndBnKSACgAAAAA.',
Wi='Wildfire:BAAALgAECgcJBwAAAA==.',
Wo='Wooties:BAAALgAECgcJCgABLgAECgkJQgABAEYfAA==.',
Wy='Wyleriya:BAABLgAECn84AAIaAAkJzQk9bQBhAQAaAAkJzQk9bQBhAQAAAA==.',
Xa='Xanthas:BAAALgADCgQJBAAAAA==.',
Xc='Xcella:BAAALgAECgUJCAAAAA==.',
Xe='Xephon:BAAALgADCgcJBwAAAA==.',
Xi='Xina:BAAALgAECgEJAQAAAA==.',
Xw='Xweakling:BAAALgADCgYJCAABLgAFFAQJDwAEAEobAA==.',
Xy='Xyn:BAAALgADCggJCAABLgAECggJCgAMAAAAAA==.',
Ya='Yamonu:BAAALgADCgEJAQAAAA==.',
Ye='Yelizaveta:BAABLgAECn8YAAINAAYJbwRZvADNAAANAAYJbwRZvADNAAAAAA==.',
Yl='Ylfcwen:BAAALgAECgEJAQAAAA==.',
Yo='Yodey:BAACLgAFFH8MAAICAAQJOB/aRABrAQACAAQJOB/aRABrAQAuAAQKfzEAAgIACQlwI54HADkDAAIACQlwI54HADkDAAAA.Yoovee:BAAALgAECggJCAAAAA==.',
Yu='Yuaetrende:BAACLgAFFH8OAAIjAAQJex4CDQBBAQAjAAQJex4CDQBBAQAuAAQKfzIAAiMACQlzI9wDABMDACMACQlzI9wDABMDAAAA.Yumii:BAABLgAECn8hAAMWAAkJPSUjAgCJAwAWAAkJECUjAgCJAwAhAAYJ/yH2DgBNAgAAAA==.',
Za='Zack:BAAALgAECgYJEwAAAA==.Zaerie:BAAALgADCgcJBwAAAA==.Zagul:BAAALgAECgUJCAAAAA==.Zalarah:BAAALgAECgUJDQAAAA==.Zalarilia:BAAALgAECgEJAQAAAA==.Zanoo:BAAALgADCgYJBwAAAA==.Zaphod:BAAALgAECgMJAwAAAA==.Zardan:BAABLgAECn8mAAIaAAgJvQ3hBwAoAQAaAAgJvQ3hBwAoAQAAAA==.',
Zi='Ziegler:BAAALgADCgYJBgAAAA==.',
Zu='Zuggasaurus:BAABLgAECn8eAAUOAAkJexg+CABMAgAOAAkJMRg+CABMAgAdAAUJoRU1IwA2AQAFAAYJ+BIvBQAbAQASAAIJVg1sqQBhAAAAAA==.Zuggerker:BAAALgAECggJCwABLgAECgkJHgAOAHsYAA==.Zugglite:BAABLgAECn8oAAQKAAgJMCEyFwBYAgAKAAgJMCEyFwBYAgAPAAQJ2xotHwAaAQAJAAEJdgmCtAEoAAABLgAECgkJHgAOAHsYAA==.Zulthar:BAABLgAECn8aAAIDAAgJ8Qo4rAAnAQADAAgJ8Qo4rAAnAQAAAA==.',
['Äs']='Äshborn:BAABLgAECn8oAAICAAkJIQ58XwCqAQACAAkJIQ58XwCqAQAAAA==.Ästra:BAAALgADCggJCAAAAA==.',
['Æi']='Æix:BAEALgAECgEJAQABLgAFFAgJGQADALkOAA==.',
['Æl']='Ælxx:BAEALgAECgYJBwABLgAFFAgJGQADALkOAA==.',
['Ðe']='Ðeathless:BAAALgADCgUJBQAAAA==.',
['Øm']='Ømnium:BAABLgAECn82AAIJAAcJbgseuwAPAQAJAAcJbgseuwAPAQAAAA==.',
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
