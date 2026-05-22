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

local lookup = {'DeathKnight-Unholy','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Shadow','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','Mage-Frost','Shaman-Enhancement','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Discipline','Shaman-Elemental','Evoker-Devastation','Evoker-Preservation','Druid-Restoration','Monk-Brewmaster','Paladin-Holy','Priest-Holy','Evoker-Augmentation','Shaman-Restoration','Druid-Balance','Mage-Arcane','Paladin-Protection','Monk-Mistweaver','Warrior-Fury','DeathKnight-Blood','DemonHunter-Devourer','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','Monk-Windwalker','Warrior-Arms',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Acaval:BAABLgAFFH8GAAIBAAMJLB23TgAWAQABAAMJLB23TgAWAQAAAA==.Accursed:BAACLgAFFH8JAAICAAMJ4CMDAgA4AQACAAMJ4CMDAgA4AQAuAAQKfyIAAgIACAl4JqsAAFYDAAIACAl4JqsAAFYDAAAA.Achanthu:BAAALgADCgcJBwAAAA==.',
Ad='Adol:BAAALgADCgMJAwAAAA==.Aduayro:BAAALgADCgQJBAAAAA==.',
Ae='Aerolias:BAAALgAECgQJBgAAAA==.',
Al='Aleighta:BAAALgAECggJEAAAAA==.Allocer:BAAALgADCgMJAwAAAA==.Alyianna:BAAALgADCgEJAQAAAA==.Alyx:BAAALgADCgMJBQAAAA==.',
Am='Amadia:BAAALgAECgMJBgAAAA==.',
An='Anahu:BAAALgADCgUJBwAAAA==.Anaia:BAAALgADCgEJAgAAAA==.Anamae:BAAALgAECgYJEQAAAA==.Andagard:BAAALgADCgEJAQAAAA==.Angrael:BAAALgADCgEJAgAAAA==.',
Ao='Aoi:BAAALgADCgcJBwABLgAECgYJFgADADYYAA==.',
Ap='Apogee:BAAALgADCgEJAQAAAA==.',
Ar='Arcey:BAAALgAECgIJAgAAAA==.',
As='Asatrath:BAAALgAECgYJDQAAAA==.Ashkillz:BAABLgAECn8UAAIEAAcJcRy8FADXAQAEAAcJcRy8FADXAQAAAA==.Ashtuck:BAAALgAECgYJCQAAAA==.Aspectoflol:BAAALgAECgYJCAAAAA==.Astrea:BAAALgAECgEJAQAAAA==.',
At='Atlantis:BAAALgAECggJEQAAAA==.',
Av='Avenger:BAAALgADCgMJAwABLgAECgYJBQAFAAAAAA==.Averissa:BAAALgAECgMJAwAAAA==.',
Az='Azazely:BAAALgAECgkJCAAAAA==.',
Ba='Badoussi:BAAALgAECgMJBgABLgAECgUJCwAFAAAAAA==.Bahnanahamok:BAAALgAECgEJAQAAAA==.Baiguang:BAAALgADCgUJBwAAAA==.Baja:BAAALgAECgQJBQAAAA==.Balodir:BAAALgAECgQJBQAAAA==.Bananas:BAACLgAFFH8TAAIGAAYJ9CA3BgDRAQAGAAYJ9CA3BgDRAQAuAAQKfxoAAgYACAn8Ij0RAAYDAAYACAn8Ij0RAAYDAAAA.',
Be='Beefomancer:BAAALgAECgQJBQABLgAECgkJJgAHAGgaAA==.Belan:BAABLgAECn8ZAAIIAAgJwxGJbABiAQAIAAgJwxGJbABiAQAAAA==.Belladin:BAABLgAECn8gAAIGAAkJ0x/THgCyAgAGAAkJ0x/THgCyAgAAAA==.',
Bl='Blameurself:BAAALgAECggJCwAAAA==.Blamezuko:BAAALgAECgUJBgABLgAECggJCwAFAAAAAA==.Blaster:BAAALgAECgEJBgAAAA==.Blite:BAAALgADCgQJDQAAAA==.Bluethain:BAAALgADCggJFgAAAA==.',
Bo='Bombakaap:BAAALgAECgYJCwAAAA==.Bomburst:BAABLgAECn8ZAAIJAAUJrRE5FgDeAAAJAAUJrRE5FgDeAAAAAA==.Bonelespizza:BAACLgAFFH8HAAIBAAIJOQqFSACTAAABAAIJOQqFSACTAAAuAAQKfzcAAwEACQlhH9sjAK8CAAEACQmHHtsjAK8CAAoABgmKH5AGAL0BAAAA.Boogiebabe:BAAALgAECgcJBwAAAA==.',
Br='Braye:BAAALgADCgMJAwAAAA==.Bresnick:BAAALgADCgkJEgAAAA==.Briaris:BAACLgAFFH8GAAIHAAMJIw2RFADtAAAHAAMJIw2RFADtAAAuAAQKfyAABAcACAm+HDgIAGsCAAcACAm+HDgIAGsCAAsAAQkuC2cwAC4AAAwAAQkIAvruACcAAAAA.Bruel:BAAALgADCgUJBQAAAA==.',
Bu='Bullschmidt:BAAALgAECgYJDwAAAA==.Burntout:BAAALgAECgEJAQABLgAFFAYJEwABAMYbAA==.',
['Bê']='Bêz:BAAALgAECgEJAQAAAA==.',
['Bë']='Bëz:BAABLgAECn8fAAICAAcJ/R1sBQD6AQACAAcJ/R1sBQD6AQAAAA==.',
Ca='Caducious:BAAALgADCgkJEgAAAA==.Calabretta:BAAALgAECgEJAQAAAA==.Capziesh:BAAALgADCgYJDwAAAA==.Casteel:BAAALgAECggJDAAAAA==.',
Ch='Chaindemon:BAAALgADCgIJBAAAAA==.Charysmaa:BAAALgADCgQJDQAAAA==.Cheoekar:BAAALgAECgYJBwABLgAFFAUJFQANAPMTAA==.Chlorìne:BAAALgAECgQJBQAAAA==.',
Co='Cobey:BAAALgAECgYJEQAAAA==.Coca:BAAALgADCgEJAQAAAA==.Corgi:BAAALgAECgYJEAAAAA==.Cosmicjay:BAECLgAFFH8FAAIOAAMJMBMGHgDhAAAOAAMJMBMGHgDhAAAuAAQKfxgAAg4ACAmqILMKAG0CAA4ACAmqILMKAG0CAAAA.Cosmicnova:BAEALgAECgYJDQABLgAFFAMJBQAOADATAA==.Costa:BAAALgAECgEJAQAAAA==.',
Cr='Crentacles:BAABLgAECn8bAAIOAAgJCxZSGADNAQAOAAgJCxZSGADNAQAAAA==.Critshade:BAAALgAECgYJDQAAAA==.Crow:BAAALgAFFAUJGgAAAQ==.',
Da='Daffodil:BAABLgAECn8aAAMPAAcJKQ/fCABVAQAPAAcJKQ/fCABVAQAQAAMJ2wK6JwBfAAAAAA==.Dannyscream:BAAALgADCgcJBwABLgAECgIJAgAFAAAAAA==.Dannyshoot:BAAALgAECgIJAgAAAA==.Dantreess:BAACLgAFFH8OAAIRAAQJSAsQIwD2AAARAAQJSAsQIwD2AAAuAAQKfx8AAhEACQl+HEkdAFMCABEACQl+HEkdAFMCAAAA.Darkshiver:BAAALgADCgEJAgABLgAECgEJBgAFAAAAAA==.Dawnslight:BAAALgAECgYJDwAAAA==.',
De='Deathlypants:BAAALgAECgIJAwAAAA==.Dedebop:BAAALgADCgIJAgAAAA==.Deiside:BAAALgADCgkJCQAAAA==.Demonwolfss:BAAALgAECgQJBAABLgAFFAcJGgASAFgfAA==.Denareyeth:BAAALgADCgkJCQAAAA==.Dephiance:BAAALgAECgEJAQABLgAECggJHgANAB4RAA==.Destroo:BAAALgADCgUJBgAAAA==.',
Dh='Dhiva:BAAALgAECgYJEAAAAA==.',
Di='Diabla:BAABLgAECn8XAAITAAYJeCTQFwBTAgATAAYJeCTQFwBTAgAAAA==.Diamanda:BAAALgADCgcJBgAAAA==.Dinsfirë:BAAALgADCgMJAwAAAA==.Diothorn:BAABLgAECn8UAAIGAAYJqQqZmAD3AAAGAAYJqQqZmAD3AAAAAA==.Divanas:BAAALgAECgYJCgAAAA==.Divi:BAABLgAECn8WAAIUAAYJSyRiCwBlAgAUAAYJSyRiCwBlAgAAAA==.',
Do='Doxa:BAAALgADCgIJAgAAAA==.',
Dr='Dragonboi:BAABLgAECn8VAAIVAAYJexHNNQACAQAVAAYJexHNNQACAQAAAA==.Drpepperz:BAAALgAECgcJCwAAAA==.',
Du='Durgan:BAAALgADCgQJBAAAAA==.Durock:BAAALgADCgQJBAABLgAECgcJDAAFAAAAAA==.',
Dy='Dymondsmashr:BAABLgAECn8hAAITAAcJJwnZNwAcAQATAAcJJwnZNwAcAQAAAA==.',
El='Elementz:BAAALgADCgYJCwAAAA==.Elfsa:BAAALgADCgYJBgAAAA==.Ellayria:BAAALgAECgYJCgAAAA==.',
Em='Emberrose:BAAALgADCgkJEwAAAA==.',
En='Endra:BAAALgADCgYJBgAAAA==.Ensetral:BAAALgADCgQJBAAAAA==.Envymytalent:BAAALgADCgQJBwABLgAECgUJBQAFAAAAAA==.',
Er='Eraleth:BAAALgADCgEJAQAAAA==.Eric:BAAALgADCgYJCQAAAA==.',
Ev='Evangaline:BAAALgADCgUJCQAAAA==.Everydae:BAACLgAFFH8FAAIVAAMJEAssGwCUAAAVAAMJEAssGwCUAAAuAAQKfyYAAhUACQnTH78HAKACABUACQnTH78HAKACAAAA.',
Ez='Eztradez:BAEALgADCgcJCwABLgAECggJDgAFAAAAAA==.',
Fa='Fakedruid:BAAALgAECgcJDgABLgAECgkJJgAHAGgaAA==.Falarzer:BAAALgADCgIJAgAAAA==.',
Fe='Feledris:BAAALgADCgYJBgAAAA==.Feybeasts:BAAALgADCgcJDAAAAA==.Feárbomber:BAAALgADCgcJDgABLgAECgYJIQASAM0kAA==.',
Ff='Ffand:BAABLgAECn8WAAIMAAYJ5x8AOwCeAQAMAAYJ5x8AOwCeAQAAAA==.',
Fh='Fharia:BAAALgADCgQJBAAAAA==.',
Fl='Flarewalker:BAAALgAECgYJAQAAAA==.Flawless:BAAALgAECgEJAQAAAA==.Flayr:BAAALgADCgQJBAAAAA==.Flopper:BAAALgADCgIJAgAAAA==.',
Fo='Fortitude:BAAALgAECgUJBQAAAA==.',
Fu='Funkymonk:BAAALgADCgEJAQAAAA==.Fusky:BAABLgAECn8dAAIWAAgJRxPEIgDmAQAWAAgJRxPEIgDmAQAAAA==.',
Fy='Fynn:BAACLgAFFH8IAAIJAAMJ3w0ZBwDcAAAJAAMJ3w0ZBwDcAAAuAAQKfyAAAwkACAnFFwwLABwCAAkACAnFFwwLABwCABYAAQmjAYipACQAAAAA.',
Ga='Galadria:BAABLgAFFH8JAAIXAAMJKgzOHwDPAAAXAAMJKgzOHwDPAAAAAA==.Ganeda:BAAALgAECgcJDAAAAA==.',
Ge='Geraldini:BAAALgAECgMJAwAAAA==.Gerwik:BAABLgAECn8aAAIMAAcJ2xTpRQB3AQAMAAcJ2xTpRQB3AQAAAA==.',
Gi='Ging:BAAALgADCggJCAAAAA==.',
Go='Goatpaladin:BAAALgAECgYJDQAAAA==.Goibniu:BAAALgADCgEJAQAAAA==.Goldenlock:BAAALgAECgYJBgAAAA==.Goliather:BAAALgADCgEJAQAAAA==.Govana:BAAALgAECgYJBwAAAA==.',
Gr='Greenleaves:BAAALgAECggJEgAAAA==.Greenpepperz:BAAALgADCgIJAgAAAA==.Gregsh:BAABLgAECn8iAAMIAAgJSBAtVgCYAQAIAAgJSBAtVgCYAQAYAAEJ6APUIQAkAAAAAA==.Grimward:BAAALgAECgYJBgAAAA==.Grosmash:BAAALgADCgEJAQAAAA==.',
Gu='Guay:BAAALgADCggJDAAAAA==.Guccisniper:BAAALgAECgkJBQAAAA==.Gummifishz:BAAALgADCgcJBwAAAA==.Gummiwormz:BAABLgAECn8XAAITAAgJHRexEQA8AgATAAgJHRexEQA8AgAAAA==.',
Ha='Hailin:BAABLgAECn8sAAIGAAkJ5xlMIwAxAgAGAAkJ5xlMIwAxAgAAAA==.Halfheal:BAAALgAECggJDAAAAA==.Halrem:BAAALgAECgEJAQAAAA==.Hatamarü:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8UAAIZAAYJ1Bk8EQBYAQAZAAYJ1Bk8EQBYAQAAAA==.',
He='Hellman:BAAALgADCgUJCQAAAA==.',
Hi='Hightroller:BAABLgAECn8iAAIMAAgJVxHIPACXAQAMAAgJVxHIPACXAQAAAA==.Hima:BAABLgAECn8WAAIDAAYJNhi8GABUAQADAAYJNhi8GABUAQAAAA==.',
Ho='Holyjenkins:BAAALgADCgkJDgAAAA==.Holysathh:BAAALgAECgUJDgABLgAECgcJDAAFAAAAAA==.Holysmoked:BAAALgADCgIJAgAAAA==.Homulily:BAAALgADCggJGwAAAA==.Hornggry:BAAALgAECgQJAwABLgAECgcJFgASALwcAA==.Horngrry:BAAALgAECgQJCAABLgAECgcJFgASALwcAA==.Horngryer:BAAALgAECgMJAwABLgAECgcJFgASALwcAA==.Horngryerr:BAABLgAECn8WAAISAAcJvBzeIwDjAQASAAcJvBzeIwDjAQAAAA==.Horngryish:BAAALgADCgEJAQABLgAECgcJFgASALwcAA==.Hortler:BAAALgAECgQJBAAAAA==.Howlingdeath:BAAALgAECgMJBQABLgAECggJKAAaAI0ZAA==.',
Hu='Huntingpants:BAABLgAECn8XAAILAAgJ4ww1DQBBAQALAAgJ4ww1DQBBAQAAAA==.',
Il='Ilovebagels:BAAALgADCgYJBgAAAA==.',
Im='Imkillho:BAAALgAECgQJBwABLgAECgcJFgASALwcAA==.',
In='Inspiredbox:BAAALgAECgMJBAAAAA==.Inverness:BAAALgAECgEJAQAAAA==.',
It='Ithax:BAAALgADCgcJAQAAAA==.',
Ja='Jacobsangle:BAAALgAECgEJAQABLgAECgEJBgAFAAAAAA==.Jankismith:BAABLgAECn8eAAIaAAYJsg+XOQDxAAAaAAYJsg+XOQDxAAAAAA==.Jayy:BAABLgAECn8hAAIHAAcJ3g6lHABqAQAHAAcJ3g6lHABqAQAAAA==.',
Je='Jelqmaxxing:BAAALgADCgcJBwABLgAFFAcJFwAbANkfAA==.Jenny:BAABLgAECn8oAAIGAAcJVRmwSgCdAQAGAAcJVRmwSgCdAQAAAA==.Jeralt:BAAALgADCgUJCQAAAA==.',
Ji='Jiraku:BAAALgAECgcJDwAAAA==.Jitoflight:BAAALgAECgYJBgAAAA==.',
Jo='Jolencila:BAAALgADCgEJAQAAAA==.Jozzartt:BAAALgAECgYJDAAAAA==.',
Ju='Junieb:BAAALgAECggJEQAAAA==.',
Ka='Kachiko:BAAALgADCggJFAAAAA==.Kaethas:BAAALgADCgEJAgAAAA==.Kaia:BAAALgAFFAEJAQAAAA==.Kamerth:BAABLgAECn8aAAMNAAcJHgZtLQANAQANAAcJHgZtLQANAQAEAAYJsgdlNwDiAAAAAA==.Kapnkrunch:BAAALgAECgUJBQAAAA==.Karluron:BAAALgAECggJDwAAAA==.Karlutros:BAABLgAECn8kAAIEAAgJ8xLNGwCSAQAEAAgJ8xLNGwCSAQAAAA==.Katastrafia:BAAALgAECgIJAgAAAA==.Katowo:BAAALgAECgQJBQABLgAFFAUJEAAcAB4mAA==.Katuwuagain:BAABLgAFFH8QAAIcAAUJHiaHBAC6AQAcAAUJHiaHBAC6AQAAAA==.Kazure:BAABLgAECn8lAAIQAAkJAgozHgCQAQAQAAkJAgozHgCQAQAAAA==.',
Ke='Keiforius:BAAALgADCgcJCwAAAA==.Kelilia:BAABLgAECn8zAAIbAAkJQw6jHAC6AQAbAAkJQw6jHAC6AQAAAA==.Keybricker:BAAALgAECgcJDwABLgAECgkJJgAHAGgaAA==.',
Kh='Khaôtic:BAABLgAECn8XAAIdAAYJCRlITQBOAQAdAAYJCRlITQBOAQAAAA==.Khuno:BAAALgAECgYJCAAAAA==.',
Ki='Killzero:BAAALgAECgQJBwAAAA==.Kiraeshh:BAABLgAECn8ZAAIIAAcJ/RJjZgBwAQAIAAcJ/RJjZgBwAQAAAA==.Kittykat:BAAALgAECgEJAQAAAA==.',
Ko='Korngry:BAAALgADCgMJAwABLgAECgcJFgASALwcAA==.',
Kr='Krakkin:BAAALgADCgYJDgAAAA==.Kralkatorrik:BAAALgADCgcJBwAAAA==.Krenil:BAAALgADCgYJGAAAAA==.Krieash:BAAALgADCggJCAAAAA==.Krumpas:BAAALgADCgMJAwABLgAECgcJFgASALwcAA==.',
Ky='Kyllea:BAAALgAECgYJEAAAAA==.',
['Kä']='Kätniss:BAAALgADCgcJBwAAAA==.',
La='Laaksy:BAACLgAFFH8HAAMPAAQJGQYGBQDNAAAPAAQJZwUGBQDNAAAVAAEJOwcURwA/AAAuAAQKfx4AAg8ACAl+EOwHAHEBAA8ACAl+EOwHAHEBAAAA.Ladraina:BAAALgADCggJCwAAAA==.Landock:BAAALgADCgYJFwAAAA==.Lavaca:BAABLgAECn8iAAQeAAkJOyNnAgBbAgAfAAgJwSGBCQD5AgAeAAYJDSNnAgBbAgAgAAYJIR/dBgCoAQABLgAFFAMJBgABACwdAA==.',
Le='Legar:BAAALgAFFAEJAQAAAA==.Lemmefreak:BAAALgAECgQJAwAAAA==.Leotart:BAACLgAFFH8FAAIRAAIJowOGRQBlAAARAAIJowOGRQBlAAAuAAQKfykAAhEACAm7EJ46AGIBABEACAm7EJ46AGIBAAAA.Leprechaune:BAAALgAECgMJAwAAAA==.Leticia:BAAALgAECgkJDgAAAA==.Lexyluthorr:BAAALgADCgIJAgAAAA==.',
Li='Linaraline:BAAALgADCgUJBQAAAA==.Lindiin:BAAALgADCgEJAQAAAA==.Lizawizah:BAAALgADCgEJAgAAAA==.',
Lo='Lortnok:BAAALgAECgQJCwAAAA==.Lotharmage:BAAALgAECgYJCwAAAA==.',
Lu='Ludoshel:BAAALgADCgEJAQAAAA==.Luminescent:BAAALgADCgIJAgAAAA==.Luwwin:BAAALgAECgEJAQAAAA==.',
Ly='Lyx:BAAALgADCgYJBwAAAA==.',
['Lí']='Líanna:BAAALgAECgcJDQAAAA==.',
['Lö']='Lögäñ:BAAALgAECgcJCAAAAA==.',
Ma='Magnessa:BAAALgAFFAEJAQAAAA==.Mandrakethan:BAAALgADCgkJHAAAAA==.Mannafest:BAEALgADCgYJBgAAAA==.Mano:BAAALgADCgMJAwAAAA==.Marist:BAAALgAECggJEQAAAA==.Marwowi:BAAALgADCgQJBAAAAA==.Maxumuss:BAAALgAECgYJBQAAAA==.',
Me='Meliodäs:BAAALgAECgEJAQAAAA==.Memelord:BAAALgADCgEJAQABLgADCgEJAQAFAAAAAA==.Mewlockian:BAAALgADCgUJBQAAAA==.',
Mi='Mianceden:BAABLgAECn8aAAIhAAYJkRz5EQB5AQAhAAYJkRz5EQB5AQAAAA==.Miku:BAAALgAECgYJBwABLgAECgkJLAAGAOcZAA==.Milent:BAABLgAECn8iAAIMAAcJhhbmQQCFAQAMAAcJhhbmQQCFAQAAAA==.Miquiztli:BAAALgAECgkJAwAAAA==.',
Mj='Mjolniïr:BAAALgAECgEJAgAAAA==.',
Mo='Moarteas:BAAALgADCgQJAgAAAA==.Moondew:BAAALgADCgEJAQAAAA==.Moral:BAAALgADCgkJEAAAAA==.',
Ms='Msspelled:BAABLgAECn8bAAQiAAYJxhuBCwA2AQAiAAYJaBqBCwA2AQAjAAQJMRE5ogC6AAAkAAIJ/hSULQA4AAAAAA==.',
Mv='Mvpiam:BAAALgAECgQJCwAAAA==.',
Mx='Mximus:BAAALgADCgEJAQABLgAECgYJBQAFAAAAAA==.',
My='Mystí:BAAALgAECggJDgAAAA==.',
Na='Nabstar:BAAALgADCgYJBgABLgAECgkJLQANAI8gAA==.Nabstarr:BAABLgAECn8tAAMNAAkJjyAkAwA6AwANAAkJjyAkAwA6AwAUAAEJRgOUhQArAAAAAA==.Namtar:BAAALgAECgEJAgAAAA==.Nasroth:BAABLgAECn8nAAIbAAcJdhTbPACxAQAbAAcJdhTbPACxAQAAAA==.Nasstina:BAAALgADCgEJAQAAAA==.Nastyfear:BAAALgADCggJEwAAAA==.',
Ne='Newagebeo:BAAALgADCgEJAQAAAA==.',
Ni='Niibyter:BAABLgAECn8dAAIhAAcJThzBDADSAQAhAAcJThzBDADSAQAAAA==.Niriti:BAAALgADCgYJBgAAAA==.',
No='Nowisforever:BAAALgADCgEJAgAAAA==.',
Ny='Nymneria:BAAALgAECgEJAQABLgAECgYJBQAFAAAAAA==.',
Od='Odînson:BAAALgADCgUJBQAAAA==.',
Ol='Oldgreyone:BAABLgAECn8UAAMRAAYJ2RClWADpAAARAAYJ2RClWADpAAAXAAYJcgpqNwDdAAAAAA==.',
On='Onlyheelz:BAAALgAECgQJBwAAAA==.Onlylocks:BAABLgAECn8eAAMjAAgJWxITQwCTAQAjAAgJZxETQwCTAQAkAAUJFRB2KgAXAQAAAA==.',
Oo='Oobi:BAAALgADCgIJAgAAAA==.',
Op='Opalais:BAABLgAECn8ZAAMEAAgJhw9QIwBXAQAEAAgJhw9QIwBXAQAUAAQJRAh8aACLAAAAAA==.',
Or='Orangedrives:BAAALgADCgUJBwAAAA==.Oreeoreo:BAABLgAECn8hAAIBAAgJIxFvYABfAQABAAgJIxFvYABfAQAAAA==.Orlathil:BAAALgADCgkJCQABLgAECggJIgAUAGQRAA==.Orlis:BAABLgAECn8iAAIUAAgJZBGMHgCGAQAUAAgJZBGMHgCGAQAAAA==.Oroe:BAAALgAECgYJDAAAAA==.',
Pa='Pallydan:BAAALgAECgMJBAAAAA==.Pandamunx:BAAALgAECgMJAQAAAA==.',
Pe='Peludita:BAABLgAECn8WAAQRAAcJox0RMwDdAQARAAcJox0RMwDdAQAXAAcJhBqfJADYAQAlAAEJsCCtKQBUAAAAAA==.Perona:BAAALgADCgYJBgAAAA==.Perséfone:BAAALgAECgYJDAABLgAECggJDgAFAAAAAA==.',
Ph='Philanthropy:BAABLgAECn8kAAMQAAgJeRlbCAAjAgAQAAgJeRlbCAAjAgAVAAcJlRRJJgBYAQAAAA==.Philtwifdloa:BAAALgADCgEJAQAAAA==.',
Pi='Pitchfiend:BAAALgAECgYJBgAAAA==.Pizzeroloko:BAAALgADCgcJBwABLgAFFAMJBgAHACMNAA==.',
Pl='Plumh:BAAALgADCgIJAgAAAA==.Pläze:BAAALgAECgYJEgAAAA==.',
Pn='Pnut:BAAALgAECgMJAwAAAA==.',
Po='Poppy:BAAALgAECgcJDQAAAA==.',
Pr='Praîmfaya:BAAALgAECgQJBQAAAA==.Primeangus:BAAALgAECgkJCQAAAA==.',
Pu='Punchpup:BAABLgAECn8pAAImAAgJpBOaHAB4AQAmAAgJpBOaHAB4AQAAAA==.',
Py='Pyronorish:BAAALgADCgYJFAAAAA==.Pytthia:BAABLgAECn8eAAMNAAgJHhESIgBfAQANAAcJyhISIgBfAQAEAAcJcRGWJABOAQAAAA==.',
['Pä']='Pändamonium:BAAALgADCgcJBQAAAA==.',
Qu='Quicknclever:BAAALgADCgYJCQAAAA==.',
Ra='Randamonk:BAAALgAECgUJBQAAAA==.Raptalia:BAAALgADCgUJBQABLgAECgkJLAAGAOcZAA==.Raziel:BAABLgAECn8RAAIdAAgJSRk+NAAoAgAdAAgJSRk+NAAoAgAAAA==.',
Re='Reagin:BAAALgADCgUJBQAAAA==.Recon:BAAALgAECgEJAQABLgAFFAQJCwAlADsDAA==.Relacks:BAAALgADCgEJAQAAAA==.Reldruin:BAAALgAECgQJCQAAAA==.Rem:BAAALgADCgUJBQAAAA==.',
Rh='Rhaena:BAABLgAECn8XAAIGAAgJkQrUbwBDAQAGAAgJkQrUbwBDAQAAAA==.',
Ri='Rikiriki:BAABLgAECn8YAAMXAAYJuQKSSgCLAAAXAAYJuQKSSgCLAAARAAYJFgLwggBtAAAAAA==.',
Ro='Rochausia:BAAALgADCgMJAwAAAA==.Ronkey:BAAALgAECgkJBgAAAA==.Ronkzar:BAAALgAECgEJAQAAAA==.Rotskar:BAAALgADCggJDAAAAA==.',
Rp='Rpgovan:BAAALgAECgQJBAAAAA==.',
Ru='Rubidious:BAAALgADCgEJAQAAAA==.Ruth:BAABLgAECn8UAAIVAAgJNQqWLQArAQAVAAgJNQqWLQArAQAAAA==.',
Sa='Sakai:BAAALgADCgYJBgAAAA==.Saltydog:BAAALgADCgYJCwAAAA==.Sandstone:BAAALgAECgEJAgAAAA==.Saratar:BAAALgADCgIJAgAAAA==.Sarlaana:BAAALgAECgEJAQAAAA==.Sashayleft:BAAALgAECgcJDgAAAA==.Satrazath:BAAALgAECgUJCQAAAA==.',
Sc='Scurge:BAAALgAECgIJAwABLgAECgYJBQAFAAAAAA==.',
Se='Secretlight:BAAALgADCgcJDAAAAA==.Secretmage:BAAALgADCgcJCAAAAA==.Seizo:BAAALgAECgYJDwAAAA==.Setal:BAABLgAECn8lAAMVAAgJwBf8FwDIAQAVAAgJwBf8FwDIAQAPAAEJIxHfPAA7AAAAAA==.',
Sg='Sgtpepperz:BAAALgADCgYJBgAAAA==.',
Sh='Shadovar:BAAALgADCgIJAgAAAA==.Shambio:BAAALgADCgEJAwAAAA==.Shammanized:BAAALgADCgkJCgAAAA==.Shamurloc:BAACLgAFFH8NAAIOAAUJrB3nDABbAQAOAAUJrB3nDABbAQAuAAQKfyQAAw4ACQn2I2sBALIDAA4ACQn2I2sBALIDABYABgkbGOpCAHUBAAAA.Shayee:BAAALgADCgEJAQAAAA==.Sheenatonic:BAAALgAECgUJCAAAAA==.Sheenzilla:BAABLgAECn8lAAMVAAgJGwXbNwD4AAAVAAgJGwXbNwD4AAAQAAYJIQGDOACnAAAAAA==.Shelltear:BAAALgADCgYJCAAAAA==.Shelwreth:BAAALgAECgYJDAAAAA==.Shigeko:BAAALgAECgMJAwAAAA==.Shikarra:BAAALgADCgkJFAAAAA==.Shindei:BAAALgADCgYJBgAAAA==.Shoinked:BAABLgAECn8wAAIOAAgJow45JwBbAQAOAAgJow45JwBbAQAAAA==.Shâmwów:BAAALgAECgEJAQAAAA==.',
Si='Sices:BAAALgADCgkJHwAAAA==.Sifodyas:BAAALgADCggJCAAAAA==.Silentpaw:BAABLgAECn8hAAISAAYJzSTlDwACAgASAAYJzSTlDwACAgAAAA==.',
Sl='Slak:BAAALgAECgkJDgAAAA==.',
Sm='Smallchaos:BAABLgAECn8eAAIDAAcJwBF0GwA5AQADAAcJwBF0GwA5AQAAAA==.Smallpaws:BAAALgADCgUJCgABLgAECgcJHgADAMARAA==.Smallêntropy:BAAALgAECgYJEQAAAA==.Smelt:BAAALgAECgIJCgAAAA==.Smuurfette:BAEALgAECggJDgAAAA==.',
Sn='Snøt:BAAALgADCgcJDAAAAA==.',
So='Sokáar:BAAALgAECgEJAQAAAA==.Solarflare:BAAALgAECgcJAgAAAA==.Solofarm:BAAALgADCgIJAgAAAA==.',
Sp='Spriest:BAEALgAECgUJCAABLgAECggJDgAFAAAAAA==.',
St='Stabbytrout:BAABLgAECn8VAAIfAAkJKheEGgAuAgAfAAkJKheEGgAuAgAAAA==.Steeb:BAAALgAECgcJBwAAAA==.Stickyjr:BAAALgADCgEJAQAAAA==.Stormtalon:BAAALgADCgIJAgAAAA==.',
Su='Sugondis:BAACLgAFFH8IAAImAAYJtBJeCwAqAQAmAAYJtBJeCwAqAQAuAAQKfxUAAiYACQn1IXAGABkDACYACQn1IXAGABkDAAEuAAUUBwkXABsA2R8A.Sunetra:BAAALgAECggJEQAAAA==.Sunraku:BAAALgAECgEJAwABLgAECgEJBgAFAAAAAA==.Sunshine:BAAALgAECgYJDgAAAA==.',
['Sà']='Sàlanis:BAAALgAECgEJAQABLgAECgQJBgAFAAAAAA==.',
['Sã']='Sãlanis:BAAALgAECgQJBgAAAA==.',
Ta='Taehyung:BAAALgAECggJDgAAAA==.Taloki:BAAALgADCgYJIAAAAA==.Tatavete:BAAALgADCgUJBQAAAA==.Tatsuhisa:BAAALgAECgcJCwAAAA==.Tazdingo:BAAALgADCgMJAwAAAA==.',
Te='Telaliah:BAAALgADCgEJAQAAAA==.Terregoat:BAABLgAECn8hAAMWAAYJ2AcPbACnAAAWAAUJAAUPbACnAAAOAAYJFwNQUQCaAAAAAA==.',
Ti='Tinny:BAAALgAECgEJAwAAAA==.Tippshunter:BAABLgAECn8mAAIHAAkJaBrRCQBCAgAHAAkJaBrRCQBCAgAAAA==.',
To='Tonton:BAAALgAECgEJAQAAAA==.Toph:BAACLgAFFH8KAAMPAAQJihgjAgBPAQAPAAQJshYjAgBPAQAVAAEJFyHyHgBbAAAuAAQKfyEABA8ACQmwIVQJAEwCAA8ABwkqIVQJAEwCABUAAwlgHktKAK0AABAAAwljBE89AIAAAAAA.Tophdh:BAABLgAECn8fAAICAAkJfSK6AQD/AgACAAkJfSK6AQD/AgABLgAFFAQJCgAPAIoYAA==.',
Tr='Traydle:BAAALgADCgkJCQABLgAECggJJQASADoZAA==.Troncho:BAAALgAECgUJDgAAAA==.Trydel:BAAALgADCgQJBAABLgAECggJJQASADoZAA==.Tryit:BAAALgAECgQJBAABLgAECggJJQASADoZAA==.Trythefox:BAABLgAECn8lAAISAAgJOhnhGQCZAQASAAgJOhnhGQCZAQAAAA==.',
Ts='Tseris:BAAALgAECgQJBwAAAA==.Tsukihana:BAAALgADCggJCAAAAA==.',
Tu='Tuini:BAABLgAECn8XAAMWAAgJpRq0FQBJAgAWAAgJpRq0FQBJAgAOAAEJ4QDAlwAXAAAAAA==.',
Ty='Tydis:BAABLgAECn8iAAIGAAgJ7goSawBNAQAGAAgJ7goSawBNAQAAAA==.',
['Tá']='Tálonstorm:BAABLgAECn8hAAInAAYJDQbXIgDWAAAnAAYJDQbXIgDWAAAAAA==.',
Ul='Ultra:BAAALgAECgEJAQAAAA==.',
Un='Unknownlord:BAAALgADCgUJBQAAAA==.Unotankhealz:BAAALgADCgMJAwAAAA==.Untamed:BAAALgADCgkJCwAAAA==.',
Va='Vaehunt:BAAALgADCgMJBAABLgAFFAQJDAAdALESAA==.Vaesar:BAAALgADCgUJBgABLgAFFAQJDAAdALESAA==.Vaesara:BAACLgAFFH8MAAIdAAQJsRKGKQApAQAdAAQJsRKGKQApAQAuAAQKfywAAh0ACQmAIWwFAAUDAB0ACQmAIWwFAAUDAAAA.Valfenrys:BAAALgAECgEJAgAAAA==.Valkarrius:BAAALgADCgIJAgAAAA==.Vani:BAABLgAECn8WAAIUAAUJCQ6qNQDgAAAUAAUJCQ6qNQDgAAAAAA==.',
Ve='Velora:BAAALgAECgQJBAAAAA==.',
Vi='Vilthrax:BAAALgAECgQJBAAAAA==.',
Vo='Voidwrath:BAAALgADCgcJEQAAAA==.Vormav:BAAALgAECgcJCwABLgADCgMJAwAFAAAAAA==.',
Wa='Wadorinramps:BAAALgAECgYJCwABLgAECgcJDAAFAAAAAA==.Waffleiron:BAABLgAECn8XAAQNAAYJyyIdIgCDAQANAAYJyyIdIgCDAQAUAAMJsx6VSwAKAQAEAAQJKRCENgDnAAAAAA==.Watermelon:BAAALgAECgUJCwABLgAECgYJBQAFAAAAAA==.',
Wf='Wforwumbo:BAAALgADCgEJAQAAAA==.',
Wh='Whalaski:BAABLgAECn8iAAIMAAkJ5xDnJwDvAQAMAAkJ5xDnJwDvAQAAAA==.',
Wi='Wickedsin:BAAALgAECgYJEAAAAA==.',
Wo='Woggieboggie:BAAALgAECgkJDAAAAA==.',
Wr='Wreckitman:BAACLgAFFH8PAAIRAAUJYBOzEAB6AQARAAUJYBOzEAB6AQAuAAQKfx0AAhEACQlYHt0HAP8CABEACQlYHt0HAP8CAAAA.',
Xa='Xaalath:BAABLgAECn8aAAIIAAcJyQV+mwAJAQAIAAcJyQV+mwAJAQAAAA==.',
['Xé']='Xéno:BAABLgAECn8ZAAIQAAgJSwhvIQBwAQAQAAgJSwhvIQBwAQAAAA==.',
Ya='Yaperbitally:BAAALgAECggJEgAAAA==.Yasia:BAAALgAECgMJAwAAAA==.',
Ye='Yellowsnowto:BAAALgADCgUJBQAAAA==.Yersn:BAAALgAECgEJAQAAAA==.',
Yo='Yobaz:BAAALgADCgUJCAAAAA==.Yohanan:BAAALgADCgYJBgAAAA==.',
Za='Zappya:BAAALgAECgYJBgAAAA==.Zarinah:BAAALgAECgQJBAAAAA==.Zarorisk:BAAALgAECgUJCwAAAA==.',
Ze='Zerø:BAAALgADCgcJBgAAAA==.Zetz:BAAALgADCgcJBwAAAA==.Zewse:BAAALgAECgEJAgAAAA==.',
Zi='Ziggiee:BAAALgAECgMJAwAAAA==.Ziggs:BAABLgAECn8cAAIHAAYJ+Bd8EgCbAQAHAAYJ+Bd8EgCbAQAAAA==.Zigzags:BAAALgADCgMJAwAAAA==.',
Zo='Zodiara:BAABLgAECn8aAAIGAAgJXxoUTwD1AQAGAAgJXxoUTwD1AQAAAA==.',
Zu='Zuesb:BAAALgADCgUJBgAAAA==.',
Zy='Zyvidria:BAABLgAECn8VAAIPAAYJPRMQCgA4AQAPAAYJPRMQCgA4AQAAAA==.',
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
