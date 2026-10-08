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

local lookup = {'Paladin-Retribution','Shaman-Elemental','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Rogue-Assassination','Priest-Holy','DemonHunter-Havoc','Warlock-Destruction','Paladin-Holy','Shaman-Restoration','DeathKnight-Blood','Warlock-Demonology','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Warrior-Arms','Druid-Restoration','Druid-Balance','Paladin-Protection','Priest-Discipline','Warrior-Fury','Rogue-Subtlety','Monk-Windwalker','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Enhancement','Warrior-Protection','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Achkmed:BAAANQADCggIEQAAAA==.',
Ad='Adelaid:BAAANQAECgEIAQABNQAFFAUICgABAJ0QAA==.',
Ae='Aethelle:BAAANQADCggICAAAAA==.',
Ak='Akalon:BAABNQAECoEmAAICAAgKjQkicQCdAQACAAgKjQkicQCdAQAAAA==.',
Al='Alexandrìte:BAAANQADCgcIEQAAAA==.Allfrost:BAAANQADCggIEwAAAA==.Aluda:BAAANQAECgUIEQAAAA==.',
An='Anùbis:BAAANQADCgIIAgAAAA==.',
Ao='Aoeina:BAABNQAECoEhAAMDAAgKSxnJgABkAgADAAgKVxfJgABkAgAEAAIKvhUfKgCAAAAAAA==.',
Ap='Apollo:BAABNQAECoEYAAIFAAcKHibQGwAPAwAFAAcKHibQGwAPAwAAAA==.',
Ar='Arcanelotus:BAAANQADCgIIAwAAAA==.Arctus:BAAANQADCgcIBwAAAA==.Ariaves:BAAANQAECgcIEQAAAA==.Arlind:BAAANQADCgcIFwAAAA==.Arthara:BAAANQABCgQIBQAAAA==.',
As='Askeral:BAAANQAECgEIAQAAAA==.Astelana:BAAANQAECgUIEQAAAA==.',
At='Atanatari:BAAANQADCgcIGwABNQAECgYIDgAGAAAAAA==.Athennah:BAAANQADCgQIBAAAAA==.',
Ba='Bassotan:BAAANQAECgcIEwAAAA==.Baticus:BAAANQADCgcIBwAAAA==.',
Be='Beleva:BAAANQAECgIIBQAAAA==.',
Bj='Bjornagain:BAAANQADCggIEAAAAA==.Björne:BAAANQADCggIFAAAAA==.',
Bl='Blackendmoon:BAAANQAECgUIDwAAAA==.Blackløtus:BAAANQAECggIEAAAAA==.Bloodedge:BAAANQAECgYIDwAAAA==.Bloodklaat:BAAANQADCggICAAAAA==.Bloodnight:BAABNQAECoEWAAIBAAgKMg+9rQCLAQABAAgKMg+9rQCLAQAAAA==.Bluebubbles:BAAANQADCggIIQAAAA==.Bluéyes:BAAANQAECgUICAAAAA==.Blvckscvl:BAABNQAECoEfAAIFAAkKAhzINgCjAgAFAAkKAhzINgCjAgAAAA==.Blynna:BAAANQADCgYICQAAAA==.',
Br='Brannik:BAAANQAECgUIDAAAAA==.Breña:BAAANQADCggIGAAAAA==.Broadleaf:BAAANQAECgQICAAAAA==.',
Ca='Camiliana:BAAANQADCgUIBQAAAA==.',
Ce='Cellulight:BAAANQAECgYIEgAAAA==.',
Ch='Charizard:BAAANQAECgcIGAAAAQ==.Chelais:BAAANQAECgcICAABNQABCgIIAgAGAAAAAA==.Cherrycola:BAAANQAECgQICQAAAA==.Chobits:BAAANQAECgQIBAAAAA==.',
Co='Coppertopp:BAAANQADCgQJBQAAAA==.Corvany:BAAANQAECgUICwAAAA==.',
Cr='Crawley:BAABNQAECoFHAAIHAAgKFB2GFQCrAgAHAAgKFB2GFQCrAgAAAA==.Crazalulla:BAAANQADCgcIBwAAAA==.Creeder:BAABNQAECoEdAAIBAAcKqQ7UswB+AQABAAcKqQ7UswB+AQAAAA==.',
Da='Dagoland:BAAANQADCggIBQAAAA==.Dainty:BAAANQADCggICgABNQAFFAUIDgAFAIgTAA==.',
De='Deaanor:BAAANQAECgMIBAAAAA==.Deathcòw:BAAANQAECgYICwAAAA==.Deween:BAAANQAECgYIDwAAAA==.',
Di='Dionysuz:BAAANQAECgcICwAAAA==.Disdekay:BAAANQAECgMIAgABNQAECgYICgAGAAAAAA==.',
Do='Dojoro:BAAANQAECgQICwAAAA==.Dorc:BAAANQADCgMIAwAAAA==.Dotsarelocks:BAAANQAECgIIAgAAAA==.',
Dr='Dradyos:BAAANQAECgUIBQAAAA==.Draegare:BAAANQAFFAEIAQAAAA==.Drdeer:BAAANQADCgUIBgAAAA==.',
Ee='Eelecurb:BAAANQADCggIDwAAAA==.',
Ei='Eisysae:BAAANQABCgIJAwAAAA==.',
El='Eliard:BAAANQABCggICQAAAA==.Ellå:BAAANQADCgUIBQABNQAECggIKgAIAHkcAA==.',
Er='Erisynn:BAEANQADCgUIBQABNQAECgkJRAAJAIMUAA==.',
Et='Eternalx:BAAANQAECgEIAQAAAA==.',
Ev='Evang:BAAANQAECgUIDwAAAA==.Everd:BAAANQAECgYIDwAAAA==.',
Fi='Fiametta:BAABNQAECoEZAAIKAAcK7xmyCwAxAgAKAAcK7xmyCwAxAgAAAA==.Firerain:BAAANQADCggJEQAAAA==.',
Fl='Flameward:BAAANQADCgYIBgAAAA==.',
Fo='Forkingidiot:BAAANQAECgQIBAAAAA==.Forodin:BAAANQADCgYIBgABNQADCggIFAAGAAAAAA==.Foxymizzy:BAAANQAECgQIBAABNQAECggIHwALANweAA==.',
Fr='Freadrick:BAAANQADCgEIAQABNQADCggIFAAGAAAAAA==.Frostknight:BAAANQAECgQIBAAAAA==.',
Fu='Funsize:BAABNQAECoEqAAIIAAgKeRwZLwCMAgAIAAgKeRwZLwCMAgAAAA==.Furyfangd:BAAANQADCgYIBwAAAA==.',
Ga='Gazzlok:BAAANQADCggIDgAAAA==.',
Ge='Gesen:BAAANQADCggIFQAAAA==.',
Gl='Gloriance:BAAANQAECgUIDwAAAA==.',
Go='Gondra:BAAANQABCgIIBAABNQAECgUICwAGAAAAAA==.Gortalon:BAAANQABCgIIAgAAAA==.',
Ha='Haplo:BAAANQAECgEIAQAAAA==.',
He='Hellmet:BAAANQAECgIJAgAAAQ==.Hey:BAABNQAECoEjAAMMAAkKSyBgGAD3AgAMAAkKSyBgGAD3AgACAAQKOQcN0gC+AAAAAA==.',
Ho='Holythot:BAAANQAECgIIAwAAAA==.',
Hu='Huogmi:BAAANQADCgcIBwAAAA==.',
Il='Ilharra:BAAANQAECgEIAgAAAA==.Ilililili:BAAANQAECgEIAQAAAA==.Illee:BAAANQAECgQICgAAAA==.',
Im='Impgangpimp:BAEANQAECgcIEwAAAA==.Imturtle:BAABNQAECoEgAAINAAcK0SLfGwC4AgANAAcK0SLfGwC4AgABNQAECgkJJQAOAIsXAA==.',
Ir='Irmis:BAAANQAECgUICAAAAA==.',
Iu='Iupiter:BAAANQAECgIIAgAAAA==.',
Iy='Iyahlieairia:BAAANQAECgMIBAAAAA==.',
Iz='Izabeth:BAAANQAECgYIDwAAAA==.',
Ja='Jamella:BAABNQAECoEcAAMBAAcK2xkPeQAKAgABAAcK2xkPeQAKAgALAAQK1QWezAC7AAAAAA==.',
Je='Jesüschrist:BAAANQAECgEIAQAAAA==.',
Ji='Jiglestd:BAAANQADCgYICAAAAA==.',
Ju='Judeath:BAAANQABCggICQABNQADCggIGAAGAAAAAA==.',
Ka='Kabocha:BAAANQAECgcIDgAAAA==.Katsa:BAAANQADCgQIBgAAAA==.Kawi:BAAANQABCgIIAwAAAA==.',
Ki='Kiraneem:BAABNQAECoEaAAIFAAcKfxgmawAQAgAFAAcKfxgmawAQAgAAAA==.Kittie:BAABNQAECoEmAAIMAAgKUhcmTwD8AQAMAAgKUhcmTwD8AQAAAA==.Kittynip:BAAANQABCgQIBAABNQAECgQIBAAGAAAAAA==.',
Kr='Krinj:BAABNQAECoEdAAMPAAcKCR5eKwALAgAPAAcKCR5eKwALAgAQAAEKOQv1ywA0AAAAAA==.Kristov:BAAANQAECgUIBQAAAA==.',
Kt='Ktariani:BAAANQADCgUIBQAAAA==.',
Ky='Kyarla:BAAANQAECgMIAwAAAA==.Kyden:BAAANQADCgEIAQAAAA==.',
La='Lazulie:BAAANQADCgcIBwAAAA==.',
Le='Leahim:BAABNQAECoFHAAINAAgKWSBZFgDjAgANAAgKWSBZFgDjAgAAAA==.Ledani:BAABNQAECoEaAAMIAAUKmRxScACUAQAIAAUKmRxScACUAQARAAQKXw5sRgDdAAAAAA==.Leonato:BAAANQADCgEIAQAAAA==.',
Li='Lilbulky:BAAANQADCgQIBAABNQAECgcIFQASAA4aAA==.',
Lo='Lohith:BAABNQAECoEdAAIMAAcKjAVHmAAdAQAMAAcKjAVHmAAdAQAAAA==.Lonedawg:BAAANQAECgEIAQAAAA==.Lourival:BAAANQAECgQJBAAAAA==.Lovécoil:BAAANQAECgYICwAAAA==.',
Lu='Lunâ:BAAANQAECgYJEgAAAA==.',
['Lë']='Lëw:BAAANQAECgYICAAAAA==.',
Ma='Maggnolya:BAAANQAECgQIBAAAAA==.Marsyx:BAABNQAECoEdAAIIAAcK7xucRwApAgAIAAcK7xucRwApAgAAAA==.Matidan:BAAANQAECgUIDQAAAA==.Mayael:BAABNQAECoEjAAMQAAgK2hqELgBVAgAQAAgKvxqELgBVAgAPAAcKeA7PQACAAQAAAA==.',
Me='Medreaux:BAABNQAECoFLAAMIAAkKEyAaEQAqAwAIAAgK6SMaEQAqAwARAAEKdgCdhwACAAAAAA==.Merrei:BAAANQAECgcIDwAAAA==.Meta:BAAANQADCggICAABNQAECgcIHQANAGIXAA==.Metalknyte:BAABNQAECoEaAAINAAcKxRW2RwC6AQANAAcKxRW2RwC6AQAAAA==.',
Mi='Miniknyte:BAABNQAECoEcAAMTAAgKWQ5bKACsAQATAAgKWQ5bKACsAQAUAAEK9AE1tgAZAAAAAA==.',
Mo='Mohu:BAAANQADCgcIBwAAAA==.Monkey:BAAANQADCgcICgAAAA==.Moonsz:BAAANQADCggIKAAAAA==.Mooseonloose:BAAANQAECggIBAAAAA==.Morandus:BAAANQAECgEIAQAAAA==.Moraria:BAAANQADCgMIAwAAAA==.Morgrathh:BAAANQADCgYIBgAAAA==.',
My='Mychelle:BAAANQAECgQIEwAAAA==.',
Na='Nakryn:BAAANQAECgYIEAAAAA==.Naryeth:BAAANQADCgEIAQAAAA==.Natorn:BAABNQAECoEdAAISAAcKwSJIUAB+AgASAAcKwSJIUAB+AgAAAA==.Nay:BAAANQAECgcJCQAAAA==.',
Ne='Nemrod:BAAANQAECgEIAQAAAA==.Nezum:BAAANQADCgYIFQAAAA==.',
Ni='Nickoli:BAAANQAECgEIAQAAAA==.Niterend:BAABNQAECoEVAAISAAcKDhrHZwA5AgASAAcKDhrHZwA5AgAAAA==.',
No='Nojomoto:BAAANQADCgcIBwAAAA==.Norabel:BAAANQADCgQICAAAAA==.',
['Nø']='Nøxxi:BAABNQAECoEZAAIKAAcK2BiVDQAUAgAKAAcK2BiVDQAUAgAAAA==.',
Ob='Obbimcanood:BAAANQADCgIIAgAAAA==.',
Ok='Okbloomer:BAAANQAECgcICwABNQAFFAYIDgAIAJ4YAA==.',
Ol='Oldben:BAABNQAECoEbAAMBAAcKuhCiuQBxAQABAAcKuhCiuQBxAQAVAAMKuwAIXwA8AAAAAA==.',
Or='Oriel:BAABNQAECoEaAAIWAAcKHwfUDgAoAQAWAAcKHwfUDgAoAQAAAA==.',
Ov='Ovy:BAAANQAECgEIAQAAAA==.',
Pa='Paleblueeye:BAAANQADCgIIAgAAAA==.Panda:BAAANQAECgMIAwAAAA==.',
Pi='Pixystix:BAAANQADCgYIDAABNQAECgQIEwAGAAAAAA==.',
Pl='Plop:BAAANQADCgcIDQABNQAECgUICwAGAAAAAA==.Plumpcheeks:BAAANQADCggIDQAAAA==.',
Po='Poc:BAAANQAECgUICwAAAA==.Poundya:BAAANQADCgYICgAAAA==.',
Pr='Prinsana:BAABNQAECoEaAAIVAAcKwRWUIQCqAQAVAAcKwRWUIQCqAQAAAA==.',
Pu='Purquis:BAAANQAECgYICQAAAA==.',
Ra='Raeve:BAAANQADCgYIBgAAAA==.Raidkicker:BAAANQADCgEIAQABNQAECgIIAgAGAAAAAA==.',
Re='Reaperlord:BAAANQAECgUIEQAAAA==.',
Ri='Rizzardofoz:BAAANQADCgMIAwAAAA==.',
Rl='Rllybuffnerd:BAAANQAECggICQAAAA==.',
Ro='Rodikus:BAABNQAECoEgAAMIAAgKJRwuLQCUAgAIAAgKJRwuLQCUAgARAAEKpRtDYgBPAAAAAA==.',
Sa='Saiaa:BAABNQAECoEZAAIHAAcKTwb7SQBSAQAHAAcKTwb7SQBSAQAAAA==.Sakeena:BAAANQAECgEIAQAAAA==.Samará:BAAANQADCgQICAAAAA==.Sarleigh:BAAANQADCgIIAgAAAA==.Sattia:BAAANQAECgUJDQAAAA==.',
Sh='Shenanygins:BAAANQADCgMIAwAAAA==.Shendalla:BAAANQABCgQIBAAAAA==.Shinokishi:BAAANQAECgUIDQAAAA==.',
Si='Silentninjaa:BAABNQAECoEdAAIXAAcKHwyiDwCMAQAXAAcKHwyiDwCMAQAAAA==.Simphunter:BAEANQAECgYIDAABNQAECgcIEwAGAAAAAA==.Sinfel:BAAANQAECgQICwAAAA==.Sit:BAAANQADCggICAAAAA==.',
Sk='Skoriko:BAABNQAECoEdAAMYAAcKDBt2FAAyAgAYAAcKDBt2FAAyAgAHAAMK2gy6bwCdAAAAAA==.',
So='Sonett:BAAANQAECgEIAQAAAA==.Sonto:BAAANQAECgIIBAAAAA==.',
Sp='Sparks:BAAANQADCgYIBgAAAA==.Splunk:BAABNQAECoEdAAINAAcKYheQQQDYAQANAAcKYheQQQDYAQAAAA==.',
St='Staggerdaddy:BAAANQAECgQIBgAAAA==.Stariya:BAAANQAECgEIAQAAAA==.Stompinghoof:BAAANQAECgYICAAAAA==.Strawyà:BAABNQAECoEWAAMZAAcKhwqeMABcAQAZAAcKhwqeMABcAQAaAAEKWAXORwAqAAAAAA==.',
Sy='Syannara:BAAANQAECgQIBAAAAA==.Syssa:BAAANQAECgQICQABNQAECgMIBQAGAAAAAA==.',
['Sì']='Sìrocco:BAAANQAECgQIBgAAAA==.',
Ta='Taleranor:BAAANQADCggIHwAAAA==.Tamerizer:BAABNQAECoEaAAIbAAgKbA0NLQC+AQAbAAgKbA0NLQC+AQAAAA==.',
Te='Tearali:BAAANQADCgEIAQAAAA==.Teejrath:BAAANQAECgcIDAAAAA==.Teekeez:BAAANQADCggICQAAAA==.',
Th='Thekal:BAAANQADCgEIAgAAAA==.Theodorel:BAAANQAECgEIAQAAAA==.Thicchick:BAAANQAECgQIBgAAAA==.Thirge:BAAANQAECgQICwAAAA==.Thorek:BAAANQADCgcIBwAAAA==.Thundertaco:BAAANQAECgQICwAAAA==.',
Ti='Tighten:BAAANQABCgEIAQAAAA==.',
To='Tofaaway:BAAANQAECgEIAQAAAA==.Tolak:BAAANQAECgQICwAAAA==.Tormikinos:BAAANQAECgUIDwAAAA==.Torturousôwl:BAAANQAECgUIDwAAAA==.Totemknyte:BAAANQABCgUIBQABNQAECgcIGgANAMUVAA==.',
Tr='Trillianh:BAAANQADCgEIAQAAAA==.Trisky:BAABNQAECoEjAAMLAAgKNh0MLQCXAgALAAgKNh0MLQCXAgAVAAEKMw86ZwAqAAAAAA==.',
Tu='Tumblebumble:BAAANQADCgIIAgAAAA==.Turtle:BAABNQAECoElAAMOAAkKixeUUgA9AgAOAAgKfRaUUgA9AgAKAAIKvRC2UQB+AAAAAA==.',
Un='Unholyghost:BAAANQABCgUICgAAAA==.',
Va='Vadrakquin:BAAANQAECgcIDgAAAA==.Valshamommy:BAABNQAECoEbAAIcAAcK7xH5FADvAQAcAAcK7xH5FADvAQAAAA==.Vanloth:BAAANQADCgEIAQAAAA==.Vantadim:BAAANQADCgMIAwAAAA==.',
Ve='Vegito:BAAANQAECgIIBQAAAA==.',
Vi='Viverrid:BAAANQAECgEIAQAAAA==.',
Vo='Voin:BAABNQAECoEsAAIdAAkK9yQqAQC7AwAdAAkK9yQqAQC7AwAAAA==.Vorpine:BAABNQAECoEaAAMRAAcK4A8FKgCvAQARAAcK4A8FKgCvAQAIAAcKShDeeAB3AQAAAA==.',
We='Wetkittie:BAAANQADCgYIBwAAAA==.',
Wi='Wiccawitch:BAAANQADCgYIEgAAAA==.Wirhl:BAAANQAECgQICgAAAA==.',
Wo='Worthatry:BAABNQAECoEiAAIBAAgKFCKZNgDSAgABAAgKFCKZNgDSAgAAAA==.',
Xa='Xalbit:BAAANQAECgUIEwAAAA==.Xantia:BAABNQAECoEkAAITAAgKaBFzJADSAQATAAgKaBFzJADSAQAAAA==.',
Xe='Xenlo:BAAANQAECgYICAAAAA==.',
Yo='Yogurt:BAAANQADCgMJAwABNQAECgIJAgAGAAAAAA==.',
Za='Zaizel:BAAANQAECgEIAQABNQAFFAYIDgAeAHkRAA==.Zalulu:BAAANQAECgMIAwABNQAECgQIBwAGAAAAAA==.Zathennyx:BAAANQAECgMIAwAAAA==.',
Ze='Zenpai:BAAANQAECgUICwAAAA==.',
Zv='Zvorunalotus:BAAANQADCgYIDQAAAA==.',
['Ðr']='Ðread:BAAANQAECgMIAwAAAA==.',
['ßß']='ßßqñüt:BAAANQAECgUIEwAAAA==.',
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
