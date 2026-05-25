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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Vengeance','Shaman-Restoration','DemonHunter-Havoc','Priest-Shadow','Unknown-Unknown','Druid-Feral','Paladin-Retribution','Hunter-Survival','Mage-Frost','Shaman-Enhancement','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Discipline','Monk-Mistweaver','Shaman-Elemental','Evoker-Devastation','Evoker-Preservation','Druid-Restoration','Druid-Balance','Monk-Brewmaster','Paladin-Holy','Paladin-Protection','Priest-Holy','Evoker-Augmentation','Warlock-Demonology','Mage-Arcane','Warrior-Fury','DeathKnight-Blood','DemonHunter-Devourer','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Warlock-Affliction','Warlock-Destruction','Druid-Guardian','Monk-Windwalker','Warrior-Arms',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Acaval:BAACLgAFFH8IAAMBAAMJLB3ZYwAEAQABAAMJLB3ZYwAEAQACAAIJtBWhEACjAAAuAAQKfxQAAwEACQm+IToHACEDAAEACQm+IToHACEDAAIAAQlrIhsiAGUAAAAA.Accursed:BAACLgAFFH8NAAIDAAQJPyXRAACwAQADAAQJPyXRAACwAQAuAAQKfyIAAgMACAl6JqsAAFYDAAMACAl6JqsAAFYDAAAA.Achanthu:BAAALgADCgcJBwAAAA==.',
Ad='Adol:BAAALgADCgMJAwAAAA==.Aduayro:BAAALgADCgQJBAAAAA==.',
Ae='Aerolias:BAAALgAECgQJBgAAAA==.',
Al='Aleighta:BAABLgAECn8XAAIEAAkJ1QflVQAnAQAEAAkJ1QflVQAnAQAAAA==.Allocer:BAAALgADCgMJAwAAAA==.Alyianna:BAAALgADCgEJAQAAAA==.Alyx:BAAALgADCgMJBgAAAA==.',
Am='Amadia:BAAALgAECgMJBgAAAA==.',
An='Anahu:BAAALgADCgUJBwAAAA==.Anaia:BAAALgADCgEJAgAAAA==.Anamae:BAAALgAECgYJEQAAAA==.Andagard:BAAALgADCgEJAQAAAA==.Angrael:BAAALgADCgEJAgAAAA==.',
Ao='Aoi:BAAALgADCgcJBwABLgAECgcJGQAFAA0XAA==.',
Ap='Apogee:BAAALgADCgEJAQAAAA==.',
Ar='Arcey:BAAALgAECgIJAgAAAA==.',
As='Asatrath:BAAALgAECgYJDwAAAA==.Ashkillz:BAABLgAECn8aAAIGAAcJbB1PFwDpAQAGAAcJbB1PFwDpAQAAAA==.Ashtuck:BAAALgAECgYJCQAAAA==.Aspectoflol:BAAALgAECgYJCAAAAA==.Astrea:BAAALgAECgEJAQAAAA==.',
At='Atlantis:BAAALgAECggJEgAAAA==.',
Av='Avenger:BAAALgADCgMJAwABLgAECgYJBQAHAAAAAA==.Averissa:BAAALgAECgMJAwAAAA==.',
Az='Azazely:BAAALgAECgkJCAAAAA==.',
Ba='Badoussi:BAAALgAECgQJCAABLgAECgkJGgAIAMcNAA==.Bahnanahamok:BAAALgAECgEJAQAAAA==.Baiguang:BAAALgADCgUJBwAAAA==.Baja:BAAALgAECgQJBQAAAA==.Balodir:BAAALgAECgQJBQAAAA==.Bananas:BAACLgAFFH8TAAIJAAYJ9CCiCgC/AQAJAAYJ9CCiCgC/AQAuAAQKfxoAAgkACAn8Ij0RAAYDAAkACAn8Ij0RAAYDAAAA.',
Be='Beefomancer:BAAALgAECgQJBAABLgAECgkJLAAKAHobAA==.Belan:BAABLgAECn8iAAILAAkJ7RQJNAArAgALAAkJ7RQJNAArAgAAAA==.Belladin:BAABLgAECn8gAAIJAAkJ0x/THgCyAgAJAAkJ0x/THgCyAgAAAA==.',
Bl='Blameurself:BAAALgAECgkJEwAAAA==.Blamezuko:BAAALgAECgUJBgABLgAECgkJEwAHAAAAAA==.Blaster:BAAALgAECgEJBgAAAA==.Blite:BAAALgADCgQJDQAAAA==.Bluethain:BAAALgAECgMJAwAAAA==.',
Bo='Bombakaap:BAAALgAECgYJCwAAAA==.Bomburst:BAABLgAECn8dAAIMAAYJqBEtFgAZAQAMAAYJqBEtFgAZAQAAAA==.Bonelespizza:BAACLgAFFH8IAAIBAAIJOQqFSACTAAABAAIJOQqFSACTAAAuAAQKfzgAAwEACQlhH9sjAK8CAAEACQmHHtsjAK8CAAIABgmKH1gJAKsBAAAA.Boogiebabe:BAAALgAECgcJCQAAAA==.',
Br='Braye:BAAALgADCgMJAwAAAA==.Bresnick:BAAALgADCgkJEgAAAA==.Briaris:BAACLgAFFH8GAAIKAAMJIw34GADhAAAKAAMJIw34GADhAAAuAAQKfyMABAoACAmCHTgIAGsCAAoACAmCHTgIAGsCAA0AAQkuC3A2ACwAAA4AAQkIApUPAScAAAAA.Bruel:BAAALgADCgUJBQAAAA==.',
Bu='Bullschmidt:BAAALgAECgYJDwAAAA==.Burntout:BAAALgAECgEJAQABLgAFFAYJFwABAPcbAA==.',
['Bê']='Bêz:BAAALgAECgEJAQAAAA==.',
['Bë']='Bëz:BAABLgAECn8nAAIDAAgJaR/SAwBpAgADAAgJaR/SAwBpAgAAAA==.',
Ca='Caducious:BAAALgADCgkJEgAAAA==.Calabretta:BAAALgAECgEJAQAAAA==.Capziesh:BAAALgAECgQJBQAAAA==.Casteel:BAAALgAECggJDAAAAA==.',
Ch='Chaindemon:BAAALgADCgIJBAAAAA==.Charysmaa:BAAALgADCgQJDQAAAA==.Cheoekar:BAAALgAECgYJBwABLgAFFAUJFQAPAPMTAA==.Chlorìne:BAAALgAECgQJBQAAAA==.',
Co='Cobey:BAAALgAECgcJEQAAAA==.Coca:BAAALgADCgEJAQAAAA==.Corgi:BAABLgAECn8YAAIQAAgJWSF4BwD2AgAQAAgJWSF4BwD2AgAAAA==.Cosmicjay:BAECLgAFFH8FAAIRAAMJMBMCJQDWAAARAAMJMBMCJQDWAAAuAAQKfxgAAhEACAmsILsOAF0CABEACAmsILsOAF0CAAAA.Cosmicnova:BAEALgAFFAEJAQABLgAFFAMJBQARADATAA==.Costa:BAAALgAECgEJAQAAAA==.',
Cr='Crentacles:BAABLgAECn8cAAIRAAkJ2hXmFgACAgARAAkJ2hXmFgACAgAAAA==.Critshade:BAAALgAECgYJDQAAAA==.Crow:BAAALgAFFAUJJAAAAQ==.',
Da='Dadeulus:BAAALgAECgUJBQAAAA==.Daffodil:BAABLgAECn8hAAMSAAcJSRAuCgBaAQASAAcJSRAuCgBaAQATAAMJ2wJWLABeAAAAAA==.Dannyscream:BAAALgADCgcJBwABLgAECgIJAgAHAAAAAA==.Dannyshoot:BAAALgAECgIJAgAAAA==.Dantreess:BAACLgAFFH8TAAIUAAUJrgyCGwBGAQAUAAUJrgyCGwBGAQAuAAQKfyAAAxQACQl+HEkdAFMCABQACQl+HEkdAFMCABUAAQmSA2OHAB8AAAAA.Darkshiver:BAAALgADCgEJAgABLgAECgEJBgAHAAAAAA==.Dawnslight:BAABLgAECn8UAAIJAAYJtQFCGgFlAAAJAAYJtQFCGgFlAAAAAA==.',
De='Deathlypants:BAAALgAECgIJAwAAAA==.Dedebop:BAAALgADCgIJAgAAAA==.Deiside:BAAALgADCgkJCQAAAA==.Demonwolfss:BAAALgAECgQJBAABLgAFFAcJGgAWAFgfAA==.Denareyeth:BAAALgAECgUJCwAAAA==.Dephiance:BAAALgAECgEJAQABLgAECgkJJwAGAEEUAA==.Destroo:BAAALgADCgUJBgAAAA==.',
Dh='Dhiva:BAAALgAECgYJEAAAAA==.',
Di='Diabla:BAABLgAECn8XAAIXAAYJeCTQFwBTAgAXAAYJeCTQFwBTAgAAAA==.Diamanda:BAAALgADCgcJBgAAAA==.Dinsfirë:BAAALgADCgMJAwAAAA==.Diothorn:BAABLgAECn8WAAMJAAYJ5gxUtwDyAAAJAAYJqQpUtwDyAAAYAAIJig71NwBWAAAAAA==.Divanas:BAAALgAECgYJEAAAAA==.Divi:BAABLgAECn8aAAIZAAcJWiQGCADIAgAZAAcJWiQGCADIAgAAAA==.',
Do='Doxa:BAAALgADCgIJAgAAAA==.',
Dr='Dragonboi:BAABLgAECn8YAAIaAAcJYRHzMgA/AQAaAAcJYRHzMgA/AQAAAA==.Drpepperz:BAAALgAFFAEJAQAAAA==.Drägonwärior:BAAALgAECgEJAQAAAA==.',
Du='Durgan:BAAALgADCgQJBwAAAA==.Durock:BAAALgADCgQJBAABLgAFFAMJAwAHAAAAAA==.',
Dy='Dymondsmashr:BAABLgAECn8pAAIXAAgJlQgrNwBIAQAXAAgJlQgrNwBIAQAAAA==.',
El='Elementz:BAAALgADCgYJCwAAAA==.Elfsa:BAAALgADCgYJBgAAAA==.Ellayria:BAAALgAECgYJCgAAAA==.',
Em='Emberrose:BAAALgADCgkJEwAAAA==.',
En='Endra:BAAALgADCgYJBgAAAA==.Ensetral:BAAALgADCgQJBAAAAA==.Envymytalent:BAAALgADCgQJBwABLgAECgcJCgAHAAAAAA==.',
Er='Eraleth:BAAALgADCgEJAQAAAA==.Eric:BAAALgADCgYJCQAAAA==.',
Ev='Evangaline:BAAALgADCgUJCQAAAA==.Evelithillyn:BAAALgAECgEJAQABLgAECgkJEwAHAAAAAA==.Everydae:BAACLgAFFH8FAAIaAAMJEAssGwCUAAAaAAMJEAssGwCUAAAuAAQKfyYAAhoACQnUH84JAKACABoACQnUH84JAKACAAAA.',
Ez='Eztradez:BAEALgADCgcJCwABLgAECgkJFgAbAAMXAA==.',
Fa='Fakedruid:BAAALgAECgcJDgABLgAECgkJLAAKAHobAA==.Falarzer:BAAALgADCgIJAgAAAA==.',
Fe='Feledris:BAAALgADCgYJBwAAAA==.Feybeasts:BAAALgAECgYJBgAAAA==.Feárbomber:BAAALgADCgcJDgABLgAECggJKQAWACIkAA==.',
Ff='Ffand:BAABLgAECn8WAAIOAAYJ5x/VOADLAQAOAAYJ5x/VOADLAQAAAA==.',
Fh='Fharia:BAAALgADCgQJBAAAAA==.',
Fl='Flarewalker:BAAALgAECgYJAQAAAA==.Flawless:BAAALgAECgEJAQAAAA==.Flayr:BAAALgADCgQJBAAAAA==.Flopper:BAAALgADCgIJAgAAAA==.',
Fo='Fortitude:BAAALgAECgcJCgAAAA==.',
Fu='Funkymonk:BAAALgADCgEJAQAAAA==.Fusky:BAABLgAECn8fAAIEAAgJYxQSJgD8AQAEAAgJYxQSJgD8AQAAAA==.',
Fy='Fynn:BAACLgAFFH8LAAIMAAQJiAyRBgAfAQAMAAQJiAyRBgAfAQAuAAQKfyAAAwwACAnFFwwLABwCAAwACAnFFwwLABwCAAQAAQmjAYipACQAAAAA.',
Ga='Galadria:BAABLgAFFH8NAAIVAAQJWRH4GQAfAQAVAAQJWRH4GQAfAQAAAA==.Ganeda:BAAALgAECgcJDAABLgAFFAMJAwAHAAAAAA==.',
Ge='Geraldini:BAAALgAECgMJAwAAAA==.Gerwik:BAABLgAECn8gAAIOAAcJFBeWTACPAQAOAAcJFBeWTACPAQAAAA==.',
Gi='Ging:BAAALgAECgYJBwAAAA==.',
Go='Goatpaladin:BAAALgAECgYJDQAAAA==.Gogetta:BAAALgAECgEJAQAAAA==.Goibniu:BAAALgADCgEJAQAAAA==.Goldenlock:BAAALgAECgYJDAAAAA==.Goliather:BAAALgADCgEJAQAAAA==.Govana:BAAALgAECgYJBwAAAA==.',
Gr='Greenleaves:BAAALgAECggJEgAAAA==.Greenpepperz:BAAALgADCgIJAgAAAA==.Gregsh:BAABLgAECn8qAAMLAAgJUxPnUgDHAQALAAgJUxPnUgDHAQAcAAEJ6APUIQAkAAAAAA==.Grimward:BAAALgAECgYJBgAAAA==.Grosmash:BAAALgADCgEJAQAAAA==.',
Gu='Guay:BAAALgADCggJDAAAAA==.Guccisniper:BAAALgAECgkJBQAAAA==.Gummifishz:BAAALgADCgcJBwAAAA==.Gummiwormz:BAABLgAECn8fAAIXAAgJ5hvvCwCqAgAXAAgJ5hvvCwCqAgAAAA==.',
Ha='Hailin:BAABLgAECn8sAAIJAAkJ5xmMLwAhAgAJAAkJ5xmMLwAhAgAAAA==.Halfheal:BAAALgAECggJDQAAAA==.Halrem:BAAALgAECgIJAgAAAA==.Hatamarü:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8VAAIYAAYJ1BkhFQBPAQAYAAYJ1BkhFQBPAQAAAA==.',
He='Heherawr:BAAALgADCgMJAwABLgAECgQJCgAHAAAAAA==.Hellman:BAAALgADCgUJCQAAAA==.Hertzabit:BAAALgAECgEJAQABLgAFFAYJFwABAPcbAA==.',
Hi='Hightroller:BAABLgAECn8qAAIOAAkJaBqyFwBvAgAOAAkJaBqyFwBvAgAAAA==.Hima:BAABLgAECn8ZAAIFAAcJDRfVGACDAQAFAAcJDRfVGACDAQAAAA==.',
Ho='Holyjenkins:BAAALgADCgkJDgAAAA==.Holysathh:BAAALgAECgUJDgABLgAFFAMJAwAHAAAAAA==.Holysmoked:BAAALgADCgIJAgAAAA==.Homulily:BAAALgADCggJGwAAAA==.Hornggry:BAAALgAECgQJAwABLgAECggJGgAWAJ4dAA==.Horngrry:BAAALgAECgQJCAABLgAECggJGgAWAJ4dAA==.Horngryer:BAAALgAECgMJAwABLgAECggJGgAWAJ4dAA==.Horngryerr:BAABLgAECn8aAAIWAAgJnh0UIQCAAQAWAAgJnh0UIQCAAQAAAA==.Horngryish:BAAALgADCgEJAQABLgAECggJGgAWAJ4dAA==.Hortler:BAAALgAECgQJBAAAAA==.Howlingdeath:BAAALgAECgMJBQABLgAECggJLQAQAI0ZAA==.',
Hu='Huntingpants:BAABLgAECn8XAAINAAgJ5AySDwA6AQANAAgJ5AySDwA6AQAAAA==.',
Il='Ilovebagels:BAAALgADCgYJBgAAAA==.',
Im='Imkillho:BAAALgAECgQJBwABLgAECggJGgAWAJ4dAA==.',
In='Inspiredbox:BAAALgAECgMJBAAAAA==.Inverness:BAAALgAECgEJAQAAAA==.',
It='Ithax:BAAALgADCgcJAQAAAA==.',
Ja='Jacobsangle:BAAALgAECgEJAQABLgAECgEJBgAHAAAAAA==.Jankismith:BAABLgAECn8lAAIQAAcJxA4tPwAYAQAQAAcJxA4tPwAYAQAAAA==.Jayy:BAABLgAECn8pAAIKAAgJ8w53GgCsAQAKAAgJ8w53GgCsAQAAAA==.',
Je='Jelqmaxxing:BAAALgADCgcJBwABLgAFFAgJGAAdAO4dAA==.Jenny:BAABLgAECn8tAAIJAAcJghzkPwDoAQAJAAcJghzkPwDoAQAAAA==.Jeralt:BAAALgADCgUJCQAAAA==.',
Ji='Jiraku:BAAALgAECgcJDwAAAA==.Jitoflight:BAAALgAECgYJBgAAAA==.',
Jo='Jolencila:BAAALgADCgEJAQAAAA==.Jozzartt:BAAALgAECgYJDAAAAA==.',
Ju='Junieb:BAABLgAECn8ZAAILAAkJbwqOggBWAQALAAkJbwqOggBWAQAAAA==.',
Ka='Kachiko:BAAALgADCggJFAAAAA==.Kaethas:BAAALgADCgEJAgAAAA==.Kaia:BAAALgAFFAEJAQAAAA==.Kamerth:BAABLgAECn8iAAMPAAgJNwfRMQAlAQAPAAcJrwbRMQAlAQAGAAcJ8ghDNgAVAQAAAA==.Kamugi:BAAALgADCgMJAwABLgAECgkJGAATAHsOAA==.Kapnkrunch:BAAALgAECgUJBQAAAA==.Karluron:BAABLgAECn8WAAIGAAkJ8BLFFQD4AQAGAAkJ8BLFFQD4AQAAAA==.Karlutros:BAABLgAECn8mAAIGAAkJ/hEiGQDYAQAGAAkJ/hEiGQDYAQAAAA==.Katastrafia:BAAALgAECgIJAgAAAA==.Katowo:BAAALgAECgQJBQABLgAFFAUJFQAeAB4mAA==.Katuwuagain:BAACLgAFFH8VAAIeAAUJHiZHBwCsAQAeAAUJHiZHBwCsAQAuAAQKfxYAAh4ACQkxJl0AAHEDAB4ACQkxJl0AAHEDAAAA.Kazure:BAABLgAECn8rAAITAAkJcQ35EACVAQATAAkJcQ35EACVAQAAAA==.',
Ke='Keiforius:BAAALgADCgcJCwAAAA==.Kelilia:BAABLgAECn87AAIdAAkJhxA4HgDZAQAdAAkJhxA4HgDZAQAAAA==.Keybricker:BAAALgAECgcJEAABLgAECgkJLAAKAHobAA==.',
Kh='Khaôtic:BAABLgAECn8XAAIfAAYJCRmDXgBJAQAfAAYJCRmDXgBJAQAAAA==.Khuno:BAAALgAECgYJCAAAAA==.',
Ki='Killzero:BAAALgAECgQJBwAAAA==.Kiraeshh:BAABLgAECn8ZAAILAAcJ/RJJewBlAQALAAcJ/RJJewBlAQAAAA==.Kittykat:BAAALgAECgMJBQAAAA==.',
Ko='Korngry:BAAALgADCgMJAwABLgAECggJGgAWAJ4dAA==.',
Kr='Krakkin:BAAALgADCgYJEwAAAA==.Kralkatorrik:BAAALgADCgcJBwAAAA==.Krenil:BAAALgADCgYJHQAAAA==.Krieash:BAAALgADCggJCAAAAA==.Krumpas:BAAALgADCgMJAwABLgAECggJGgAWAJ4dAA==.',
Ky='Kyllea:BAABLgAECn8UAAIOAAcJjRXxUQB/AQAOAAcJjRXxUQB/AQAAAA==.',
['Kä']='Kätniss:BAAALgADCgcJBwAAAA==.',
La='Laaksy:BAACLgAFFH8JAAMSAAQJYggOBgDHAAASAAQJZwUOBgDHAAAaAAIJ9QgvQwB8AAAuAAQKfx4AAhIACAl+EJ4JAGcBABIACAl+EJ4JAGcBAAAA.Ladraina:BAAALgADCggJDAAAAA==.Landock:BAAALgADCgYJIgAAAA==.Lavaca:BAABLgAECn8nAAQgAAkJOyN5AQC9AgAhAAgJwSGBCQD5AgAgAAgJKSN5AQC9AgAiAAYJIR9kCACgAQABLgAFFAMJCAABACwdAA==.',
Le='Legar:BAAALgAFFAMJAwAAAA==.Lemmefreak:BAAALgAECgQJAwAAAA==.Leotart:BAACLgAFFH8IAAIUAAMJIgpiNwC1AAAUAAMJIgpiNwC1AAAuAAQKfykAAhQACAm7EIhCAGMBABQACAm7EIhCAGMBAAAA.Leprechaune:BAAALgAECgMJAwAAAA==.Leticia:BAAALgAECgkJDgAAAA==.Lexyluthorr:BAAALgADCgIJAgAAAA==.',
Li='Liechen:BAAALgAECgYJBgAAAA==.Linaraline:BAAALgADCgUJBQAAAA==.Lindiin:BAAALgADCgEJAQAAAA==.Lizawizah:BAAALgADCgEJAgAAAA==.',
Lo='Lortnok:BAAALgAECgUJDwAAAA==.Lotharmage:BAAALgAECgcJDwAAAA==.',
Lu='Ludoshel:BAAALgADCgEJAQAAAA==.Luminescent:BAAALgADCgIJAgAAAA==.Luwwin:BAAALgAECgEJAQAAAA==.',
Ly='Lyx:BAAALgADCgYJBwAAAA==.',
['Lí']='Líanna:BAAALgAECgcJDQAAAA==.',
['Lö']='Lögäñ:BAAALgAECggJCgAAAA==.',
Ma='Maelora:BAAALgADCgYJBgAAAA==.Magnessa:BAAALgAFFAEJAQAAAA==.Malovious:BAAALgADCgkJCQAAAA==.Mandrakethan:BAAALgADCgkJHAAAAA==.Mannafest:BAEALgADCgYJBgAAAA==.Mano:BAAALgAECgEJAQAAAA==.Marist:BAABLgAECn8ZAAMEAAkJIQ8AQgB5AQAEAAgJRwwAQgB5AQARAAEJVAUQmgAhAAAAAA==.Marwowi:BAAALgADCgQJBAAAAA==.Maxumuss:BAAALgAECgYJBQAAAA==.',
Me='Meliodäs:BAAALgAECgEJAQAAAA==.Memelord:BAAALgADCgEJAQABLgADCgEJAQAHAAAAAA==.Mewlockian:BAAALgADCgUJBQAAAA==.',
Mi='Mianceden:BAABLgAECn8gAAIjAAYJgx7YEQCjAQAjAAYJgx7YEQCjAQAAAA==.Miku:BAAALgAECgkJDQABLgAECgkJLAAJAOcZAA==.Milent:BAABLgAECn8oAAIOAAcJhhYRUwB7AQAOAAcJhhYRUwB7AQAAAA==.Mimix:BAAALgADCgEJAQAAAA==.Miquiztli:BAAALgAECgkJBQAAAA==.Mizoci:BAAALgAECgEJAQAAAA==.',
Mj='Mjolniïr:BAAALgAECgEJBAAAAA==.',
Mo='Moarteas:BAAALgADCgQJAgAAAA==.Moondew:BAAALgADCgEJAQAAAA==.Moral:BAAALgADCgkJEAAAAA==.',
Ms='Msspelled:BAABLgAECn8cAAQkAAcJYBg6DwAzAQAkAAYJaBo6DwAzAQAbAAUJOg8IoQDmAAAlAAIJ/hTpMwA2AAAAAA==.',
Mv='Mvpiam:BAAALgAECgQJDAAAAA==.',
Mx='Mximus:BAAALgADCgEJAQABLgAECgYJBQAHAAAAAA==.',
My='Mystí:BAAALgAECggJDgAAAA==.',
Na='Nabstar:BAAALgADCgYJBgABLgAECgkJNgAPAOwiAA==.Nabstarr:BAABLgAECn82AAQPAAkJ7CJHAgB/AwAPAAkJ7CJHAgB/AwAZAAEJRgOUhQArAAAGAAEJAAaIeAAoAAAAAA==.Namtar:BAAALgAECgEJAgAAAA==.Nasroth:BAACLgAFFH8FAAIdAAMJFg/OKADXAAAdAAMJFg/OKADXAAAuAAQKfygAAh0ACAlHEts8ALEBAB0ACAlHEts8ALEBAAAA.Nasstina:BAAALgADCgEJAQAAAA==.Nastyfear:BAAALgADCggJEwAAAA==.Natureterror:BAAALgADCgYJBgAAAA==.',
Ne='Newagebeo:BAAALgADCgEJAQAAAA==.',
Ni='Niibyter:BAABLgAECn8lAAIjAAgJCR+aBwBlAgAjAAgJCR+aBwBlAgAAAA==.Niriti:BAAALgADCgYJBgAAAA==.',
No='Nowisforever:BAAALgADCgEJAgAAAA==.',
Ny='Nymneria:BAAALgAECgEJAQABLgAECgYJBQAHAAAAAA==.',
Od='Odînson:BAAALgAECgEJAQAAAA==.',
Ol='Oldgreyone:BAABLgAECn8UAAMUAAYJ2RA+YwDqAAAUAAYJ2RA+YwDqAAAVAAYJcgqfQQDUAAAAAA==.',
On='Onlyheelz:BAAALgAECgQJBwAAAA==.Onlylocks:BAABLgAECn8lAAMbAAgJORWcQwC5AQAbAAgJRBScQwC5AQAlAAUJFRB2KgAXAQAAAA==.Ontius:BAAALgAECgMJAwAAAA==.',
Oo='Oobi:BAAALgADCgIJAgAAAA==.',
Op='Opalais:BAABLgAECn8dAAMGAAgJ0A8dKQBeAQAGAAgJ0A8dKQBeAQAZAAQJRAh8aACLAAAAAA==.',
Or='Orangedrives:BAAALgADCgYJCwAAAA==.Oreeoreo:BAABLgAECn8iAAIBAAgJJhFtcQBcAQABAAgJJhFtcQBcAQAAAA==.Orlathil:BAAALgADCgkJCQABLgAECgkJJAAZAEwQAA==.Orlis:BAABLgAECn8kAAIZAAkJTBDbHgCpAQAZAAkJTBDbHgCpAQAAAA==.Oroe:BAAALgAECgYJDAAAAA==.',
Pa='Pallydan:BAAALgAECgMJBAAAAA==.Pandamunx:BAAALgAECgMJAQAAAA==.',
Pe='Peludita:BAABLgAECn8WAAQUAAcJox0RMwDdAQAUAAcJox0RMwDdAQAVAAcJhBqfJADYAQAmAAEJsCCtKQBUAAAAAA==.Perona:BAAALgADCgYJBgAAAA==.Perséfone:BAAALgAECgYJCwABLgAECggJDgAHAAAAAA==.',
Ph='Philanthropy:BAABLgAECn8kAAMTAAgJeBkRCgAdAgATAAgJeBkRCgAdAgAaAAcJlxQ7LgBaAQAAAA==.Philtwifdloa:BAAALgADCgEJAQAAAA==.',
Pi='Pitchfiend:BAAALgAECgYJBgAAAA==.Pizzeroloko:BAAALgADCgcJBwABLgAFFAMJBgAKACMNAA==.',
Pl='Plumh:BAAALgADCgMJAwAAAA==.Pläze:BAAALgAECgYJEgAAAA==.',
Pn='Pnut:BAAALgAECgMJAwAAAA==.',
Po='Poppy:BAAALgAECgcJDQAAAA==.',
Pr='Prayformercy:BAAALgADCgIJAgAAAA==.Praîmfaya:BAAALgAECgQJBQAAAA==.Primeangus:BAAALgAECgkJCQAAAA==.',
Pu='Punchpup:BAABLgAECn8pAAInAAgJpRPKIQB4AQAnAAgJpRPKIQB4AQAAAA==.',
Py='Pyronorish:BAAALgADCgYJGQAAAA==.Pytthia:BAABLgAECn8nAAMGAAkJQRSLFAAEAgAGAAkJQRSLFAAEAgAPAAcJyxL9KABbAQAAAA==.',
['Pä']='Pändamonium:BAAALgAECgQJBAAAAA==.',
Qu='Quicknclever:BAAALgAECgQJAwAAAA==.',
Ra='Randamonk:BAAALgAECgUJBQAAAA==.Ranraku:BAAALgADCgEJAQAAAA==.Raptalia:BAAALgADCgcJBwABLgAECgkJLAAJAOcZAA==.Raziel:BAABLgAECn8RAAIfAAgJSRk+NAAoAgAfAAgJSRk+NAAoAgAAAA==.',
Re='Reagin:BAAALgADCgUJBQAAAA==.Recon:BAAALgAECgEJAQABLgAFFAQJDwAmAHEDAA==.Regade:BAAALgADCgkJCQABLgAECgkJJwAGAEEUAA==.Relacks:BAAALgADCgEJAQAAAA==.Reldruin:BAAALgAECgQJCQAAAA==.Rem:BAAALgADCgUJBQAAAA==.',
Rh='Rhaena:BAABLgAECn8YAAIJAAgJkgo0hABGAQAJAAgJkgo0hABGAQAAAA==.',
Ri='Rikiriki:BAABLgAECn8YAAMVAAYJuQIcVgCGAAAVAAYJuQIcVgCGAAAUAAYJFgKqkQBtAAAAAA==.',
Rn='Rndnfluffy:BAAALgAECgEJAQAAAA==.',
Ro='Robok:BAAALgADCgYJBgAAAA==.Rochausia:BAAALgADCgMJAwAAAA==.Ronkey:BAAALgAECgkJBgAAAA==.Ronkzar:BAAALgAECgMJBAAAAA==.Rotskar:BAAALgADCggJDAAAAA==.',
Rp='Rpgovan:BAAALgAECgQJBAAAAA==.',
Ru='Rubidious:BAAALgADCgEJAQAAAA==.Ruth:BAABLgAECn8iAAIaAAgJSw2MLQBfAQAaAAgJSw2MLQBfAQAAAA==.',
['Rô']='Rôflstômp:BAAALgAECgEJAQAAAA==.',
Sa='Sacini:BAAALgADCgYJBgAAAA==.Sakai:BAAALgADCgYJBgAAAA==.Saltydog:BAAALgADCgYJEAAAAA==.Sandstone:BAAALgAECgEJAgAAAA==.Saratar:BAAALgADCgIJAgAAAA==.Sarlaana:BAAALgAECgEJAQAAAA==.Sashayleft:BAAALgAECgcJDgAAAA==.Satrazath:BAAALgAECgYJDwAAAA==.',
Sc='Scurge:BAAALgAECgIJAwABLgAECgYJBQAHAAAAAA==.',
Se='Secretlight:BAAALgADCgcJDAAAAA==.Secretmage:BAAALgADCgcJCAAAAA==.Seizo:BAAALgAECgYJDwAAAA==.Setal:BAABLgAECn8uAAMaAAkJ5xtZCwCHAgAaAAkJ5xtZCwCHAgASAAEJIxHfPAA7AAAAAA==.',
Sg='Sgtpepperz:BAAALgADCgYJBgAAAA==.',
Sh='Shadovar:BAAALgADCgIJAgAAAA==.Shambio:BAAALgADCgEJAwAAAA==.Shammanized:BAAALgADCgkJCgAAAA==.Shamurloc:BAACLgAFFH8NAAIRAAUJrB3GEgBHAQARAAUJrB3GEgBHAQAuAAQKfyQAAxEACQn2I2sBALIDABEACQn2I2sBALIDAAQABgkbGOpCAHUBAAAA.Shayee:BAAALgADCgEJAQAAAA==.Sheenatonic:BAAALgAECgUJCQAAAA==.Sheenzilla:BAABLgAECn8lAAMaAAgJGwUsQAACAQAaAAgJGwUsQAACAQATAAYJIQGDOACnAAAAAA==.Shelltear:BAAALgADCgYJCAAAAA==.Shelwreth:BAAALgAECgYJDAAAAA==.Shigeko:BAAALgAECgMJAwAAAA==.Shikarra:BAAALgADCgkJFAAAAA==.Shindei:BAAALgADCgYJBgAAAA==.Shoinked:BAABLgAECn8xAAIRAAgJog6ULwBUAQARAAgJog6ULwBUAQAAAA==.Shâmwów:BAAALgAECgEJAQAAAA==.',
Si='Sices:BAAALgAECgEJAQAAAA==.Sifodyas:BAAALgADCggJCAAAAA==.Silentpaw:BAABLgAECn8pAAIWAAgJIiQHBQDXAgAWAAgJIiQHBQDXAgAAAA==.',
Sl='Slak:BAAALgAECgkJEwAAAA==.',
Sm='Smallchaos:BAABLgAECn8eAAIFAAcJwBElIgAsAQAFAAcJwBElIgAsAQAAAA==.Smallpaws:BAAALgADCgUJCgABLgAECgcJHgAFAMARAA==.Smallêntropy:BAAALgAECgcJEgAAAA==.Smelt:BAAALgAECgIJCgAAAA==.Smuurfette:BAEBLgAECn8WAAIbAAkJAxfJKgAWAgAbAAkJAxfJKgAWAgAAAA==.',
Sn='Snøt:BAAALgADCgcJDAAAAA==.',
So='Sokáar:BAAALgAECgEJAQAAAA==.Solarflare:BAAALgAECgcJAgAAAA==.Solofarm:BAAALgADCgIJAgAAAA==.',
Sp='Spriest:BAEALgAECgUJCAABLgAECgkJFgAbAAMXAA==.',
St='Stabbytrout:BAABLgAECn8VAAIhAAkJKheEGgAuAgAhAAkJKheEGgAuAgAAAA==.Steeb:BAAALgAECgcJBwAAAA==.Stickyjr:BAAALgADCgEJAQAAAA==.Stormtalon:BAAALgADCgIJAgAAAA==.',
Su='Sugondis:BAACLgAFFH8IAAInAAYJtBINDgApAQAnAAYJtBINDgApAQAuAAQKfxUAAicACQn1IXAGABkDACcACQn1IXAGABkDAAEuAAUUCAkYAB0A7h0A.Sunetra:BAABLgAECn8ZAAIJAAkJkAvfaQB7AQAJAAkJkAvfaQB7AQAAAA==.Sunraku:BAAALgAECgEJAwABLgAECgEJBgAHAAAAAA==.Sunshine:BAAALgAECgYJDgAAAA==.',
['Sà']='Sàlanis:BAAALgAECgEJAQABLgAECgQJBgAHAAAAAA==.',
['Sã']='Sãlanis:BAAALgAECgQJBgAAAA==.',
Ta='Taehyung:BAAALgAECggJDwAAAA==.Taloki:BAAALgADCgYJIAAAAA==.Tatavete:BAAALgADCgUJBQAAAA==.Tatsuhisa:BAAALgAECggJDAAAAA==.Tazdingo:BAAALgADCgMJAwAAAA==.',
Te='Telaliah:BAAALgADCgEJAQAAAA==.Terregoat:BAABLgAECn8pAAMRAAgJSARpSADhAAARAAgJSARpSADhAAAEAAUJAAXwfgCkAAAAAA==.',
Th='Thallyn:BAAALgAECgcJBwAAAA==.',
Ti='Tinny:BAAALgAECgEJBQAAAA==.Tippshunter:BAABLgAECn8sAAIKAAkJehv6BwCFAgAKAAkJehv6BwCFAgAAAA==.',
To='Tonton:BAAALgAECgEJAQAAAA==.Toph:BAACLgAFFH8KAAMSAAQJihjQAgBFAQASAAQJshbQAgBFAQAaAAEJFyHyHgBbAAAuAAQKfyEABBIACQmwIVQJAEwCABIABwkqIVQJAEwCABoAAwlgHu1WAKsAABMAAwljBE89AIAAAAAA.Tophdh:BAABLgAECn8fAAIDAAkJfSK6AQD/AgADAAkJfSK6AQD/AgABLgAFFAQJCgASAIoYAA==.',
Tr='Traydle:BAAALgADCgkJCQABLgAECggJJwAWADoZAA==.Troncho:BAAALgAECgUJDgAAAA==.Trydel:BAAALgADCgQJBAABLgAECggJJwAWADoZAA==.Tryit:BAAALgAECgQJBAABLgAECggJJwAWADoZAA==.Trythefox:BAABLgAECn8nAAIWAAgJOhkAHACmAQAWAAgJOhkAHACmAQAAAA==.',
Ts='Tseris:BAAALgAECgUJCwAAAA==.Tsukihana:BAAALgAECgUJCAAAAA==.',
Tu='Tuini:BAABLgAECn8XAAMEAAgJphqpGwBAAgAEAAgJphqpGwBAAgARAAEJ4QDAlwAXAAAAAA==.',
Ty='Tydis:BAABLgAECn8pAAIJAAgJcQtoegBZAQAJAAgJcQtoegBZAQAAAA==.',
['Tá']='Tálonstorm:BAABLgAECn8pAAIoAAgJcQYxKQD7AAAoAAgJcQYxKQD7AAAAAA==.',
Ul='Ultra:BAAALgAECgEJAQAAAA==.',
Un='Unknownlord:BAAALgADCgUJBQAAAA==.Unotankhealz:BAAALgADCgMJAwAAAA==.Untamed:BAAALgADCgkJCwAAAA==.',
Va='Vaehunt:BAAALgADCgMJBAABLgAFFAUJDgAfAOIUAA==.Vaesar:BAAALgADCgUJBgABLgAFFAUJDgAfAOIUAA==.Vaesara:BAACLgAFFH8OAAIfAAUJ4hSGMAAqAQAfAAUJ4hSGMAAqAQAuAAQKfywAAh8ACQmBIYMHAAEDAB8ACQmBIYMHAAEDAAAA.Valfenrys:BAAALgAECgEJAgAAAA==.Valkarrius:BAAALgADCgIJAgAAAA==.Vani:BAABLgAECn8aAAIZAAYJmg00NQAJAQAZAAYJmg00NQAJAQAAAA==.',
Ve='Velora:BAAALgAECgQJBAAAAA==.',
Vi='Vilthrax:BAAALgAECgYJBgAAAA==.',
Vo='Voidwrath:BAAALgADCgcJEQAAAA==.Vormav:BAAALgAECgcJCwABLgADCgMJAwAHAAAAAA==.',
Wa='Wadorinramps:BAAALgAECgYJCwABLgAFFAMJAwAHAAAAAA==.Waffleiron:BAABLgAECn8XAAQPAAYJyyIdIgCDAQAPAAYJyyIdIgCDAQAZAAMJsx6VSwAKAQAGAAQJKRBeQADjAAAAAA==.Watermelon:BAAALgAECggJEAAAAA==.',
Wf='Wforwumbo:BAAALgADCgEJAQAAAA==.',
Wh='Whalaski:BAABLgAECn8tAAIOAAkJVxSVJQAgAgAOAAkJVxSVJQAgAgAAAA==.',
Wi='Wickedsin:BAAALgAECgYJEQAAAA==.Windhurst:BAAALgAECgYJBgAAAA==.',
Wo='Woggieboggie:BAAALgAECgkJDAAAAA==.',
Wr='Wreckitman:BAACLgAFFH8VAAIUAAUJKRedEwCHAQAUAAUJKRedEwCHAQAuAAQKfx4AAhQACQlYHv8JAP0CABQACQlYHv8JAP0CAAAA.',
Xa='Xaalath:BAABLgAECn8hAAILAAcJKglYnAAnAQALAAcJKglYnAAnAQAAAA==.',
['Xé']='Xéno:BAABLgAECn8ZAAITAAgJSwhvIQBwAQATAAgJSwhvIQBwAQAAAA==.',
Ya='Yaperbitally:BAAALgAECggJEgAAAA==.Yasia:BAAALgAECgMJAwAAAA==.',
Ye='Yellowsnowto:BAAALgADCgUJBQAAAA==.Yersn:BAAALgAECgIJAwAAAA==.',
Yo='Yobaz:BAAALgADCgYJDgAAAA==.Yohanan:BAAALgADCgYJBgAAAA==.',
Za='Zappya:BAAALgAECgYJBgAAAA==.Zarinah:BAAALgAECgQJBAAAAA==.Zarorisk:BAAALgAECgcJEAABLgAECgkJGgAIAMcNAA==.Zarraz:BAAALgADCgcJCAAAAA==.',
Ze='Zerø:BAAALgADCgcJBgAAAA==.Zetz:BAAALgADCgcJBwAAAA==.Zewse:BAAALgAECgEJAgAAAA==.',
Zi='Ziggiee:BAAALgAECgMJAwAAAA==.Ziggs:BAABLgAECn8cAAIKAAYJ+Bd8EgCbAQAKAAYJ+Bd8EgCbAQAAAA==.Zigzags:BAAALgADCgMJAwAAAA==.',
Zo='Zodiara:BAABLgAECn8aAAIJAAgJXxoUTwD1AQAJAAgJXxoUTwD1AQAAAA==.',
Zu='Zuesb:BAAALgADCgUJBgAAAA==.',
Zy='Zyvidria:BAABLgAECn8ZAAISAAcJphVOCACMAQASAAcJphVOCACMAQAAAA==.',
['Ãñ']='Ãñgêl:BAAALgAECgEJAQAAAA==.',
['Øn']='Ønyx:BAAALgAECgMJBAAAAA==.',
['ße']='ßeam:BAAALgAECgEJAQAAAA==.',
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
