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

local lookup = {'Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Priest-Shadow','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','Druid-Guardian','Unknown-Unknown','Rogue-Assassination','Monk-Brewmaster','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Paladin-Holy','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Paladin-Protection','Priest-Discipline','Druid-Feral','Rogue-Subtlety','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Achkmed:BAAANQADCggIEQAAAA==.',
Ad='Adelaid:BAAANQAECgEIAQABNQAFFAYIDwABAM8SAA==.',
Ae='Aethelle:BAAANQADCggICAAAAA==.',
Ak='Akalon:BAABNQAECn9AAAICAAoKFQwkbQDZAQACAAoKFQwkbQDZAQAAAA==.',
Al='Aleckzander:BAAANQAECgMIBAABNQAECgkJKwADABglAA==.Alexandrìte:BAAANQADCgcIEQAAAA==.Allfrost:BAAANQAECgIIAwAAAA==.Altscale:BAAANQAECgYIBgAAAA==.Aluda:BAABNQAECn8hAAMEAAcKlw/4mgBEAQAEAAYKQw74mgBEAQAFAAUKgxAbQAAuAQAAAA==.',
An='Anùbis:BAAANQADCgIIAgAAAA==.',
Ao='Aoeina:BAABNQAECn8uAAMGAAoKzxUSGgCnAQAGAAoKthMSGgCnAQAHAAIKnBr4DgCcAAAAAA==.',
Ap='Apollo:BAABNQAECn8kAAIIAAkK5iUMBQCCAgAIAAkK5iUMBQCCAgAAAA==.',
Ar='Arcanelotus:BAAANQADCgIIAwAAAA==.Arctus:BAAANQADCgcIBwAAAA==.Ariaves:BAAANQAECggIEgAAAA==.Arlind:BAAANQAECgQIBQAAAA==.Artemix:BAAANQAECgQIBAAAAA==.Arthara:BAAANQABCgQIBwAAAA==.',
As='Askeral:BAAANQAECgEIAQAAAA==.Astelana:BAABNQAECn8hAAIBAAcKuwfYaQDyAAABAAcKuwfYaQDyAAAAAA==.',
At='Atanatari:BAAANQADCgcIGwABNQAECgkJGQAFACgFAA==.Athennah:BAAANQADCgQIBAAAAA==.',
Ba='Bassotan:BAABNQAECn8YAAIBAAkKawqb1AByAQABAAkKawqb1AByAQAAAA==.Baticus:BAAANQADCgcIBwAAAA==.',
Be='Beleva:BAAANQAECgIIBQAAAA==.Bezzaj:BAAANQAFFAIIAgABNQAFFAcIGQAGABgSAA==.',
Bj='Bjornagain:BAAANQAECgUICgAAAA==.Björne:BAAANQADCggIFAAAAA==.',
Bl='Blackendmoon:BAABNQAECn8eAAMJAAYKhAesbADsAAAJAAYKgAasbADsAAAKAAIKdQioygBXAAAAAA==.Blackløtus:BAAANQAECggIEAAAAA==.Bloodedge:BAAANQAECgYIDwAAAA==.Bloodklaat:BAAANQADCggICAAAAA==.Bloodnight:BAABNQAECn8YAAIBAAkK1w/nsQC7AQABAAkK1w/nsQC7AQAAAA==.Bluéyes:BAAANQAECgYICQAAAA==.Blvckscvl:BAABNQAECn8jAAIIAAkKYxxgKQDzAgAIAAkKYxxgKQDzAgAAAA==.Blynna:BAAANQADCgYICQAAAA==.',
Br='Brannik:BAAANQAECgYIEwAAAA==.Breña:BAAANQADCggIGAAAAA==.Broadleaf:BAAANQAECgQICAAAAA==.',
Ca='Camiliana:BAAANQADCgUIBQAAAA==.',
Ce='Cellulight:BAABNQAECn8kAAILAAkKAhi4DQCKAgALAAkKAhi4DQCKAgAAAA==.',
Ch='Charizard:BAAANQAECgcIGAAAAQ==.Chelais:BAAANQAECggICQABNQABCgIIAgAMAAAAAA==.Cherrycola:BAAANQAECgQICQAAAA==.Chobits:BAAANQAECgQIBAAAAA==.',
Co='Coppertopp:BAAANQADCgQJBQAAAA==.Corvany:BAAANQAECgUICwAAAA==.',
Cr='Crawley:BAABNQAECn9dAAINAAoKoRrPAwD+AQANAAoKoRrPAwD+AQAAAA==.Crazalulla:BAAANQADCgcIDgAAAA==.Creeder:BAABNQAECn8fAAIBAAkK1gwNqwDJAQABAAkK1gwNqwDJAQAAAA==.Crixus:BAAANQAECgUICgAAAA==.',
Da='Dagoland:BAAANQADCggIBQAAAA==.Dainty:BAAANQAECgIIAQABNQAFFAcIEgAIAG0WAA==.',
De='Deaanor:BAAANQAECgMIBAAAAA==.Deathcòw:BAAANQAECgYICwAAAA==.Deween:BAAANQAECggIEwAAAA==.',
Di='Diamond:BAAANQAECgEIAgAAAA==.Dionysuz:BAAANQAECgcIDQAAAA==.Disdekay:BAAANQAECgMIAgABNQAECggIDQAMAAAAAA==.',
Do='Dojoro:BAABNQAECn8ZAAIOAAgKYRAJFgCCAQAOAAgKYRAJFgCCAQAAAA==.Dorc:BAAANQADCgMIAwAAAA==.Dotsarelocks:BAABNQAECn8WAAQPAAcKJRRvBAAOAQAPAAcKJRRvBAAOAQAQAAIKagxMKwFnAAARAAEKAADTZwBSAAAAAA==.',
Dr='Dradyos:BAAANQAECgUIDgAAAA==.Draegare:BAAANQAFFAEIAQAAAA==.Drdeer:BAAANQADCgUIBgAAAA==.',
Ee='Eelecurb:BAAANQADCggIDwAAAA==.',
Ei='Eisysae:BAAANQABCgIJAwAAAA==.',
El='Eliard:BAAANQABCggICQAAAA==.Ellå:BAAANQADCgUIBQABNQAECgoKPAAEAM0gAA==.',
Er='Erisynn:BAEANQADCgUIBQABNQAFFAQICAASAJkDAA==.',
Et='Eternalx:BAAANQAECgEIAQAAAA==.',
Ev='Evang:BAABNQAECn8eAAIIAAcKPgvxQQAyAQAIAAcKPgvxQQAyAQAAAA==.Everd:BAABNQAECn8dAAIBAAcKpgmO4QBYAQABAAcKpgmO4QBYAQAAAA==.',
Fi='Fiametta:BAABNQAECn8lAAIRAAgKBBbPDAAqAgARAAgKBBbPDAAqAgAAAA==.Firerain:BAAANQADCggIEQAAAA==.',
Fl='Flameward:BAAANQADCgYIBgAAAA==.Flippi:BAAANQABCgYICAAAAA==.',
Fo='Forkingidiot:BAAANQAECgQIBAAAAA==.Forodin:BAAANQADCgYIBgABNQADCggIFAAMAAAAAA==.Foxymizzy:BAAANQAECgQIBAABNQAECgkJIAATAGsdAA==.',
Fr='Freadrick:BAAANQADCgEIAQABNQADCggIFAAMAAAAAA==.Frostknight:BAAANQAECgYICAAAAA==.',
Fu='Funsize:BAABNQAECn88AAIEAAoKzSAtAwAUAwAEAAoKzSAtAwAUAwAAAA==.',
Ga='Gardek:BAAANQAECggIAQAAAA==.Gazzlok:BAAANQADCggIDwAAAA==.',
Ge='Gesen:BAAANQADCggIFQAAAA==.',
Gl='Global:BAAANQABCgcICgABNQAECgUIBQAMAAAAAA==.Gloriance:BAABNQAECn8eAAIQAAcKJBfqLABBAQAQAAcKJBfqLABBAQAAAA==.',
Go='Gondra:BAAANQABCgIIBAABNQAECgUICwAMAAAAAA==.Gortalon:BAAANQABCgIIAgAAAA==.',
Ha='Haplo:BAAANQAECgIIBgAAAA==.',
He='Hellmet:BAAANQAECgIJAgAAAQ==.Hey:BAACNQAFFH8IAAMCAAMKvgLPHgC/AAACAAMKvgLPHgC/AAADAAIKGRk/FABWAAA1AAQKfygAAwMACgr4IMsfAOsCAAMACQpLIMsfAOsCAAIACApXCVQ1AOsAAAAA.',
Hi='Hinamori:BAAANQAECgMIBAAAAA==.',
Ho='Holythot:BAAANQAECgIIAwABNQAFFAYIFQAUANEcAA==.',
Hu='Huogmi:BAAANQAECgQIBQAAAA==.',
Il='Ilharra:BAAANQAECgMICAAAAA==.Ilililili:BAAANQAECgMIBwAAAA==.Illee:BAABNQAECn8cAAIGAAkK8gxRawDlAAAGAAkK8gxRawDlAAAAAA==.',
Im='Impgangpimp:BAEBNQAECn8mAAIQAAoKIRiICwDzAQAQAAoKIRiICwDzAQAAAA==.Imturtle:BAABNQAECn8yAAIUAAoKqSAyAwBIAgAUAAoKqSAyAwBIAgABNQAECgoKPgAQAGUZAA==.',
Ir='Irmis:BAABNQAECn8WAAMVAAkK/hbPAgCsAQAVAAgKNRPPAgCsAQAWAAYKrRcZGwCHAQAAAA==.',
It='Ithrynluin:BAAANQAECgQIBAABNQAECgkJGQAFACgFAA==.',
Iu='Iupiter:BAAANQAECggICQAAAA==.',
Iy='Iyahlieairia:BAAANQAECgMIBAAAAA==.',
Iz='Izabeth:BAABNQAECn8cAAMHAAgKFA0QEgCFAQAHAAgKFA0QEgCFAQAGAAEKQgLW1QErAAAAAA==.',
Ja='Jamella:BAABNQAECn8qAAMBAAkKHxOHmQDwAQABAAcKQxiHmQDwAQATAAkK4graNgAKAQAAAA==.',
Je='Jesüschrist:BAAANQAECgEIAgAAAA==.',
Ji='Jiglestd:BAAANQAECgEIAQAAAA==.',
Ju='Judeath:BAAANQABCggICQABNQADCggIGAAMAAAAAA==.',
Ka='Kabocha:BAAANQAECgcIDgAAAA==.Katsa:BAAANQAECgEIAQAAAA==.Kawi:BAAANQABCgIIAwAAAA==.Kayeh:BAAANQADCgIIAgAAAA==.',
Ki='Kiraneem:BAABNQAECn8iAAIIAAgK5hziYQBSAgAIAAgK5hziYQBSAgAAAA==.Kittie:BAABNQAECn82AAIDAAoKThWWFwCaAQADAAoKThWWFwCaAQAAAA==.Kittynip:BAAANQADCgQIBAABNQAECgUIBQAMAAAAAA==.',
Kr='Krinj:BAABNQAECn8fAAMJAAkKXh2FHwCPAgAJAAkKXh2FHwCPAgAKAAEKOQsF4AA0AAAAAA==.Kristov:BAAANQAECgcIBwAAAA==.',
Kt='Ktariani:BAAANQADCgYICgAAAA==.',
Ky='Kyarla:BAAANQAECgUIEAAAAA==.Kyden:BAAANQADCgEIAQAAAA==.',
La='Lazulie:BAAANQADCgcIBwAAAA==.',
Le='Leahim:BAABNQAECn9nAAIUAAoKOiKKAgB3AgAUAAoKOiKKAgB3AgAAAA==.Ledani:BAABNQAECn8mAAMEAAkKqxhpbQDWAQAEAAYKGRxpbQDWAQAFAAcKWwqdFADlAAAAAA==.Leonato:BAAANQADCgEIAQAAAA==.',
Li='Lilbulky:BAAANQAECgUIBwABNQAECggIHAAXAAIaAA==.Liriels:BAAANQAECgEIAQABNQAECgIIBgAMAAAAAA==.',
Lo='Lohith:BAABNQAECn8fAAIDAAkKDQVtjwBiAQADAAkKDQVtjwBiAQAAAA==.Lonedawg:BAAANQAECgMIBwAAAA==.Lourival:BAAANQAECgQJBAAAAA==.Lovécoil:BAABNQAECn8VAAIKAAgK9RtWBAD+AQAKAAgK9RtWBAD+AQAAAA==.',
Lu='Lunâ:BAAANQAECgYIEgAAAA==.',
['Lë']='Lëw:BAAANQAECgYICAAAAA==.',
Ma='Mageofthe:BAAANQADCgUIBQAAAA==.Maggnolya:BAAANQAECgUIBgAAAA==.Marsyx:BAABNQAECn8fAAIEAAkKvRvSKgC+AgAEAAkKvRvSKgC+AgAAAA==.Matidan:BAABNQAECn8WAAIYAAcKrhYCKAAEAgAYAAcKrhYCKAAEAgAAAA==.Mayael:BAABNQAECn8lAAMKAAkKrRomLQB/AgAKAAkKrRomLQB/AgAJAAcKuA8dUABzAQAAAA==.',
Me='Medreaux:BAABNQAECn9pAAMEAAoKRSFmBgCTAwAEAAoKRSFmBgCTAwAFAAEKdgADmQACAAAAAA==.Merrei:BAABNQAECn8cAAMSAAgKkBTiMwANAgASAAgKkBTiMwANAgAZAAYKHwlvGAAqAQAAAA==.Meta:BAAANQADCggICAABNQAECgkJHwAUABcVAA==.Metalknyte:BAABNQAECn8iAAIUAAgK7xATUQCwAQAUAAgK7xATUQCwAQAAAA==.',
Mi='Miniknyte:BAABNQAECn8rAAMaAAoKcBOdDgBYAQAaAAoKcBOdDgBYAQAbAAEKAABVyQAZAAAAAA==.',
Mo='Mohu:BAAANQADCgcIBwAAAA==.Monkey:BAAANQADCgcICgAAAA==.Moonsz:BAAANQADCggILwAAAA==.Mooseonloose:BAAANQAECggIDQAAAA==.Morandus:BAAANQAECgEIAQAAAA==.Moraria:BAAANQADCgMIAwAAAA==.Morgrathh:BAAANQADCgYIBgAAAA==.',
My='Mychelle:BAABNQAECn8iAAIcAAkK7glMFwDMAAAcAAkK7glMFwDMAAAAAA==.',
Na='Nakryn:BAABNQAECn8VAAMHAAgKowJGJADLAAAGAAcKbwKLWgH7AAAHAAYKLwJGJADLAAAAAA==.Naryeth:BAAANQADCgEIAQAAAA==.Natorn:BAABNQAECn8fAAIXAAkKeCHeJAAlAwAXAAkKeCHeJAAlAwAAAA==.Nay:BAAANQAECgcJCQAAAA==.',
Ne='Nemrod:BAAANQAECgEIAQAAAA==.Nezum:BAAANQAECgEIAQAAAA==.',
Ni='Nickoli:BAAANQAECgEIAQAAAA==.Niterend:BAABNQAECn8cAAIXAAgKAhqCNwA5AQAXAAgKAhqCNwA5AQAAAA==.',
No='Nojomoto:BAAANQADCgcIBwAAAA==.Norabel:BAAANQADCgQICAAAAA==.',
Nu='Nugehuts:BAAANQAFFAIIAgABNQAFFAkJKwAQAOMlAA==.',
['Nø']='Nøxxi:BAABNQAECn8nAAMRAAoKphdqCgBQAgARAAgKtBtqCgBQAgAQAAYK3AiBOwAZAQAAAA==.',
Ob='Obbimcanood:BAAANQADCgIIAgAAAA==.',
Ok='Okbloomer:BAAANQAECggIEAABNQAFFAcIEQAEALMXAA==.',
Ol='Oldben:BAABNQAECn8qAAMBAAcKoBCKXQAKAQABAAcKoBCKXQAKAQAdAAMK5gDHawA7AAAAAA==.',
Or='Oriel:BAABNQAECn8iAAIeAAgKQAfrEAAaAQAeAAgKQAfrEAAaAQAAAA==.',
Ov='Ovy:BAAANQAECgEIAQAAAA==.',
Pa='Paleblueeye:BAAANQADCgIIAgAAAA==.Panda:BAAANQAECgMIAwAAAA==.',
Pi='Pixystix:BAAANQADCgYIDAABNQAECgkJIgAcAO4JAA==.',
Pl='Plop:BAAANQAECgQIBAABNQAECgUIBQAMAAAAAA==.Plumpcheeks:BAAANQADCggIDQAAAA==.',
Po='Poc:BAABNQAECn8aAAIfAAcKMwkJDADeAAAfAAcKMwkJDADeAAAAAA==.Poundya:BAAANQADCgYICgAAAA==.',
Pr='Prinsana:BAABNQAECn8iAAIdAAgK0xE6JQC2AQAdAAgK0xE6JQC2AQAAAA==.',
Pu='Purquis:BAAANQAECggIEQAAAA==.',
Ra='Raeve:BAAANQADCgYIBgAAAA==.Raidkicker:BAAANQADCgEIAQABNQAECgcIFgAPACUUAA==.',
Re='Reaperlord:BAABNQAECn8hAAITAAcKOx1vEADTAQATAAcKOx1vEADTAQAAAA==.',
Ri='Rizzardofoz:BAAANQADCgMIAwAAAA==.',
Rl='Rllybuffnerd:BAAANQAECggICQAAAA==.',
Ro='Rodikus:BAABNQAECn8uAAMEAAoKmx8mIADvAgAEAAoKmx8mIADvAgAFAAEKAAANbgBOAAAAAA==.',
Sa='Saiaa:BAABNQAECn8hAAINAAgKXwVTWwBKAQANAAgKXwVTWwBKAQAAAA==.Sakeena:BAAANQAECgMIBwAAAA==.Samará:BAAANQADCgQICAAAAA==.Sarleigh:BAAANQADCgIIAgAAAA==.Sattia:BAAANQAECgYIDQAAAA==.',
Sh='Shabloink:BAAANQAECgEIAQAAAA==.Shadereaver:BAAANQAECggICAAAAA==.Shenanygins:BAAANQADCgMIAwAAAA==.Shendalla:BAAANQABCgQIBAAAAA==.Shinokishi:BAABNQAECn8cAAIUAAcK4w3mIwDnAAAUAAcK4w3mIwDnAAAAAA==.',
Si='Silentninjaa:BAABNQAECn8sAAIVAAkKFRBgBABxAQAVAAkKFRBgBABxAQAAAA==.Simphunter:BAEBNQAECn8ZAAIYAAoK+hTDIABGAgAYAAoK+hTDIABGAgABNQAECgoKJgAQACEYAA==.Sinfel:BAABNQAECn8ZAAMSAAgKSAc0WwAXAQASAAgKWQY0WwAXAQAZAAMKXwa0KgBeAAAAAA==.Sit:BAAANQADCggICAAAAA==.',
Sk='Skoriavis:BAAANQAECgEIAQABNQAECgcIHQAgADUZAA==.Skoriko:BAABNQAECn8dAAMgAAcKNRn6FgAoAgAgAAcKNRn6FgAoAgANAAMK2gwbhgCaAAAAAA==.',
Sl='Slürmp:BAAANQAECgEIAQAAAA==.',
Sn='Snowcones:BAAANQADCgUIBQAAAA==.',
So='Sonett:BAAANQAECgIIBAAAAA==.Sonto:BAAANQAECgQICAAAAA==.',
Sp='Sparks:BAAANQADCgYIBgAAAA==.Splunk:BAABNQAECn8fAAIUAAkKFxWyOAAkAgAUAAkKFxWyOAAkAgAAAA==.',
St='Staggerdaddy:BAAANQAECgQIBgAAAA==.Stariya:BAAANQAECgMIBwAAAA==.Stompinghoof:BAAANQAECgYICAAAAA==.Strapattack:BAAANQADCgcIBwAAAA==.Strawyà:BAABNQAECn8fAAMhAAgKMQwQEgAdAQAhAAgKMQwQEgAdAQAiAAEKWAUXUQAnAAAAAA==.',
Sy='Syannara:BAAANQAECgUIBQAAAA==.Syklar:BAAANQADCgEIAQAAAA==.Syssa:BAAANQAECgUIEQABNQAECgUIEAAMAAAAAA==.',
['Sì']='Sìrocco:BAAANQAECgYICwAAAA==.',
Ta='Taleranor:BAAANQAECgcIBwAAAA==.Tamerizer:BAABNQAECn8iAAIcAAkK3w8AMADNAQAcAAkK3w8AMADNAQAAAA==.',
Te='Tearali:BAAANQADCggICAAAAA==.Teejrath:BAABNQAECn8XAAQKAAkK6w7EWwChAQAKAAgKmw/EWwChAQAJAAEKzgqktAArAAAUAAEKAAB24AAeAAAAAA==.Teekeez:BAAANQADCggICQAAAA==.',
Th='Thekal:BAAANQADCgEIAgAAAA==.Theodorel:BAAANQAECgEIAQAAAA==.Thicchick:BAAANQAECgYIDAAAAA==.Thirge:BAABNQAECn8XAAIVAAYK6g2SFQBDAQAVAAYK6g2SFQBDAQAAAA==.Thorek:BAAANQADCgcIBwAAAA==.Thrushbeard:BAAANQADCgcIBwAAAA==.Thundertaco:BAABNQAECn8WAAICAAYKMQt4oQBTAQACAAYKMQt4oQBTAQAAAA==.',
Ti='Tighten:BAAANQABCgEIAQAAAA==.',
To='Toesniffer:BAAANQADCggICAAAAA==.Tofaaway:BAAANQAECgMIBwAAAA==.Tolak:BAAANQAECgYIEAAAAA==.Tormikinos:BAABNQAECn8eAAIbAAcKvwnDKgC4AAAbAAcKvwnDKgC4AAAAAA==.Torturousôwl:BAABNQAECn8XAAMEAAYKFxSlLwA/AQAEAAYKFxSlLwA/AQAeAAEK3AXeLwAlAAAAAA==.Totemknyte:BAAANQABCgUIBQABNQAECggIIgAUAO8QAA==.',
Tr='Trillianh:BAAANQADCgEIAQAAAA==.Trisky:BAABNQAECn8jAAMTAAgKNh0dNQCPAgATAAgKNh0dNQCPAgAdAAEKMw+CdQAnAAAAAA==.',
Tu='Tumblebumble:BAAANQADCgMIAwAAAA==.Turtle:BAABNQAECn8+AAMQAAoKZRnRCQAKAgAQAAkKrBfRCQAKAgARAAIKehOKTwCRAAAAAA==.',
Va='Vadrakquin:BAAANQAECggIDwAAAA==.Valshamommy:BAABNQAECn8gAAIjAAoKPhKVEwAvAgAjAAoKPhKVEwAvAgAAAA==.Vanloth:BAAANQADCgEIAgAAAA==.Vantadim:BAAANQADCgMIAwAAAA==.',
Ve='Vegito:BAAANQAECgIIBQAAAA==.Velfurry:BAAANQAECgEIAQABNQAFFAcIIwAkALoNAA==.Verlassan:BAAANQADCgcIBwAAAA==.',
Vi='Viverrid:BAAANQAECgEIAQAAAA==.',
Vo='Voinwar:BAACNQAFFH8IAAIWAAMKEhhDAQDcAAAWAAMKEhhDAQDcAAA1AAQKfzYAAhYACgp9JKABALIDABYACgp9JKABALIDAAAA.Vorpine:BAABNQAECn8kAAMFAAkKaBDsLQC2AQAFAAkKaBDsLQC2AQAEAAcKvREShACLAQAAAA==.',
We='Wetkittie:BAAANQADCgYIBwAAAA==.',
Wi='Wiccawitch:BAAANQADCgYIEwAAAA==.Wirhl:BAAANQAECgUIEgAAAA==.',
Wo='Worthatry:BAABNQAECn8nAAIBAAoKtSEYLAAXAwABAAoKtSEYLAAXAwAAAA==.',
Xa='Xalbit:BAABNQAECn8fAAIDAAcKuAMGuQD5AAADAAcKuAMGuQD5AAAAAA==.Xantia:BAABNQAECn8zAAIaAAoKQhGRBgDiAQAaAAoKQhGRBgDiAQAAAA==.',
Xe='Xenlo:BAAANQAECgYICgAAAA==.',
Yo='Yogurt:BAAANQADCgMJAwABNQAECgIJAgAMAAAAAA==.',
Za='Zaizel:BAAANQAECgEIAQABNQAFFAcIEQAlABgQAA==.Zalulu:BAAANQAECgMIAwABNQAECgQIBwAMAAAAAA==.Zathennyx:BAAANQAECgMIAwAAAA==.',
Ze='Zenpai:BAAANQAECgUICwAAAA==.',
Zv='Zvorunalotus:BAAANQADCgYIDQAAAA==.',
['Ðr']='Ðread:BAAANQAECgUICAAAAA==.',
['ßß']='ßßqñüt:BAABNQAECn8XAAIFAAYKfAl0QwAZAQAFAAYKfAl0QwAZAQAAAA==.',
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
