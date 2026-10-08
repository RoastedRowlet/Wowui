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

local lookup = {'Monk-Windwalker','Warrior-Arms','Unknown-Unknown','Shaman-Elemental','Hunter-BeastMastery','Shaman-Restoration','Priest-Discipline','Paladin-Retribution','Druid-Feral','Druid-Restoration','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Holy','Priest-Holy','Warlock-Affliction','DeathKnight-Frost','Mage-Frost','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Survival','Warlock-Demonology','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','Druid-Balance',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aahhotep:BAAANQADCgQIBAAAAA==.',
Ag='Agnestachyon:BAAANQAECgUIBgAAAA==.',
Ai='Aitwa:BAAANQADCggICAAAAA==.',
Ak='Aksnowman:BAAANQADCgYICAAAAA==.',
Al='Aliane:BAAANQAECgQICgAAAA==.Almertato:BAAANQAECgQIBAAAAA==.Alydara:BAAANQAECgUICAAAAA==.',
Am='Amoonday:BAAANQAECgIIBAAAAA==.',
An='Andes:BAAANQADCgcJCwAAAA==.',
Ar='Aramoonsong:BAABNQAECoEsAAIBAAgKrSMsCAA5AwABAAgKrSMsCAA5AwAAAA==.Aranrùth:BAABNQAECoEWAAICAAgKIRsuXgBVAgACAAgKIRsuXgBVAgAAAA==.Arastellia:BAAANQADCgQJBQAAAA==.Aretria:BAAANQAECgEIAQAAAA==.Ariean:BAAANQADCggICQAAAA==.Arthin:BAAANQABCgQIBAAAAA==.',
As='Ashbowbaby:BAAANQAECgQIBAABNQAECgYIDQADAAAAAA==.',
Au='Auraborealis:BAAANQAECgUIDAAAAA==.',
Av='Avadon:BAAANQADCggICAAAAA==.Avarice:BAAANQAECgUIDAAAAA==.',
Az='Azuael:BAAANQAECgcIBwAAAA==.',
Ba='Baberaham:BAAANQAECgEIAQAAAA==.Ballzdragon:BAAANQAECgQIBAABNQAECgkJFwAEAMkaAA==.Balzamon:BAABNQAECoEcAAICAAcKWwe3vQBQAQACAAcKWwe3vQBQAQAAAA==.Bandgeek:BAAANQAECgYIEgAAAA==.',
Be='Beegood:BAABNQAECoEcAAIFAAYKdgjLvABVAQAFAAYKdgjLvABVAQAAAA==.Beweaver:BAAANQADCggICAABNQAECgQICAADAAAAAA==.',
Bi='Biebert:BAABNQAECoEYAAICAAgKzRBBggDyAQACAAgKzRBBggDyAQAAAA==.Bizzy:BAAANQADCgcICgAAAA==.',
Bl='Blooddemon:BAAANQADCggICQABNQAECggIHwAGAFQYAA==.Bloodegg:BAABNQAECoEhAAIFAAgKLQzycwD6AQAFAAgKLQzycwD6AQAAAA==.',
Bo='Boinkadin:BAAANQADCgQIAgAAAA==.',
Br='Bradcrit:BAAANQAECgQIAgAAAA==.Braverecall:BAAANQADCgYICAAAAA==.Bredarra:BAAANQADCgYIBgAAAA==.Brewzlee:BAAANQAECgQIBgABNQAECggICgADAAAAAA==.Broomphondle:BAAANQAECgUIDgAAAA==.Brootis:BAAANQADCgYIBQAAAA==.',
Bs='Bshoottu:BAAANQAECgQIEAAAAA==.',
Bu='Bubblina:BAAANQADCgMIAwAAAA==.',
Cd='Cdub:BAAANQADCgEIAQABNQAECgYIDQADAAAAAA==.',
Ce='Celexa:BAAANQADCgQIBwAAAA==.',
Ch='Chrisando:BAAANQABCgYIBwAAAA==.Chrisswamy:BAAANQABCgYIBwAAAA==.Chromesatan:BAAANQAECggIBgABNQAECggICgADAAAAAA==.',
Ci='Cityr:BAAANQADCgUIBQAAAA==.',
Cl='Cloud:BAAANQADCggIHwAAAA==.',
Cr='Crankypal:BAAANQAECgIIAgAAAA==.Cringevoker:BAAANQAECgEIAQAAAA==.',
Cw='Cwdcannabull:BAAANQADCgcICwAAAA==.',
['Cá']='Cárl:BAAANQABCgIIAgAAAA==.',
Da='Daemage:BAAANQADCgQJBAAAAA==.Dagara:BAAANQADCgIJAgAAAA==.Daredevill:BAAANQADCgEIAQAAAA==.Darkdrittz:BAAANQAECgUICwAAAA==.',
De='Deadash:BAAANQADCgcICwABNQAECgYIDQADAAAAAA==.Deathclaw:BAAANQAECgYIEAAAAA==.Deceptiõn:BAAANQABCgYIBgAAAA==.Deldúwath:BAAANQAECgYIEgAAAA==.Demigra:BAAANQABCgYICgAAAA==.Demontyllas:BAAANQADCgYIBgAAAA==.',
Di='Dinklage:BAAANQADCgMIAwAAAA==.Dionus:BAAANQAECgYIEgAAAA==.',
Do='Doanh:BAAANQABCgYICAAAAA==.Dolorquedura:BAAANQAECgEIAQAAAA==.Domoarigato:BAAANQAECgQICAAAAA==.',
Dr='Drakuluh:BAAANQAECgMIAwAAAA==.Drapaco:BAAANQABCgMIAwAAAA==.Draucan:BAABNQAECoEcAAIHAAgKJR37AgC8AgAHAAgKJR37AgC8AgAAAA==.Dreadmoor:BAAANQADCgYIDAABNQAECgQIEAADAAAAAA==.Dribblesnot:BAAANQAECgQIEAAAAA==.Driden:BAAANQAECgYIDgAAAA==.',
Dy='Dya:BAAANQADCggICAAAAA==.',
Ec='Echolock:BAAANQAECgUIBwAAAA==.',
El='Elementálist:BAAANQADCgUIBgABNQADCggJDgADAAAAAA==.Elemetzy:BAAANQAECgQIBgAAAA==.Elkul:BAAANQAECgQICQAAAA==.Elsoned:BAAANQAECgMIBgAAAA==.',
Ev='Evokyn:BAAANQADCgEIAQAAAA==.',
Fa='Falafel:BAABNQAECoEYAAIIAAYK8RLBtgB4AQAIAAYK8RLBtgB4AQAAAA==.Fattaco:BAABNQAECoEfAAIGAAgKVBjyPQA+AgAGAAgKVBjyPQA+AgAAAA==.',
Fl='Floss:BAAANQAECgUIDAAAAA==.Flubb:BAABNQAECoEeAAMJAAkKsCCOAwBJAwAJAAkKsCCOAwBJAwAKAAEKhQNkawApAAAAAA==.Flígbot:BAAANQAECggICAAAAA==.',
Fo='Fofglass:BAAANQADCgEIAQABNQAECggIIQADAAAAAA==.Followmenot:BAAANQAECgYIEwAAAA==.Fortbuff:BAAANQAECggIEAAAAA==.',
Fr='Frostyballz:BAAANQAECgMIAwABNQAECgcIFAAIAFkdAA==.Frëyæ:BAAANQADCgQIBAABNQAECgkJFwAEAMkaAA==.',
Fu='Furgus:BAAANQAECgEIAQABNQAECgUICgADAAAAAA==.',
Fy='Fyerflise:BAAANQADCgUICQAAAA==.Fyrakkobama:BAEANQADCgYIBwABNQAECgkJHQALAPwhAA==.',
Ga='Gannador:BAAANQADCgEIAQAAAA==.',
Gg='Ggreed:BAAANQADCgEIAQAAAA==.',
Go='Gobblegobble:BAABNQAECoEZAAIMAAcK3RQYKQDaAQAMAAcK3RQYKQDaAQAAAA==.Gosudizzle:BAABNQAECoEjAAIFAAkKmSK9DwBSAwAFAAkKmSK9DwBSAwABNQAECgYIEgADAAAAAA==.',
Gr='Grippingtaco:BAAANQADCgYIBgABNQAECggIHwAGAFQYAA==.',
Gu='Gulldarilynn:BAAANQAECgMIBAAAAA==.',
Gw='Gwendolyn:BAABNQAECoEkAAIJAAgKECNCBAAsAwAJAAgKECNCBAAsAwABNQAECggILAABAK0jAA==.Gweniveere:BAAANQADCgcIBwAAAA==.',
Ha='Hakubell:BAACNQAFFIELAAINAAUK6h36BgDRAQANAAUK6h36BgDRAQA1AAQKgS0AAw0ACQoTJSADALgDAA0ACQoTJSADALgDAAgABQp1II2jAKIBAAE1AAQKBggUAA4AZBwA.Hammershock:BAAANQAECgUIDwAAAA==.Hasdiel:BAAANQAECgYIDgAAAA==.',
He='Heartim:BAAANQAECgMIAwAAAA==.Heädaches:BAAANQAECgMIBQAAAA==.',
Ho='Holynuke:BAAANQADCgcIBwABNQAFFAQICAACAJkQAA==.',
Il='Illimommy:BAACNQAFFIETAAIMAAcKWRXzAQBZAgAMAAcKWRXzAQBZAgA1AAQKgRkAAgwACQoKIKQPAOUCAAwACQoKIKQPAOUCAAAA.',
In='Inkarok:BAAANQAECgUIDgAAAA==.',
Is='Ishkode:BAABNQAECoEbAAIPAAgKxQvKCADWAQAPAAgKxQvKCADWAQAAAA==.',
It='Itachi:BAAANQAECgEIAQAAAA==.',
Iz='Izzyrael:BAAANQAECgEIAQAAAA==.',
Ja='Jalapeno:BAAANQAECgUIDAAAAA==.Jami:BAABNQAECoEXAAIQAAgKZg88NwC7AQAQAAgKZg88NwC7AQABNQADCgIJAgADAAAAAA==.',
Je='Jellybean:BAAANQADCggIFwAAAA==.',
Ji='Jitlo:BAACNQAFFIENAAIEAAYK9QzOBgDdAQAEAAYK9QzOBgDdAQA1AAQKgS8AAgQACQq6IsALAH0DAAQACQq6IsALAH0DAAAA.Jitsham:BAAANQAECgYIBgAAAA==.',
Jo='Joesa:BAAANQAECgIIAgAAAA==.',
Ka='Kalanrahl:BAABNQAECoEaAAQRAAgKkxSQCgDsAQARAAgKkxSQCgDsAQASAAYKUgooDwFNAQATAAEK1ANEDQAnAAAAAA==.Kaldenormu:BAAANQADCgQJBAAAAA==.Kashanden:BAAANQADCgcIBwABNQAECgkJIwAUAP4jAA==.',
Ke='Kemaneral:BAAANQADCgIJAgAAAA==.',
Kh='Khaiduus:BAAANQAECgYIEAAAAA==.',
Ki='Killatroll:BAAANQADCgEIAQAAAA==.Kilmonger:BAAANQADCgQJBQAAAA==.Kirinkurai:BAABNQAECoEeAAIVAAgKZxjMCAA0AgAVAAgKZxjMCAA0AgAAAA==.Kittsune:BAAANQADCgYIBwAAAA==.Kizmet:BAAANQAECgIJBQAAAA==.',
Km='Kmoniwnaleya:BAAANQADCggIFQAAAA==.',
Ko='Kottenmouth:BAABNQAECoEtAAIWAAkKyyCmAQA/AwAWAAkKyyCmAQA/AwAAAA==.',
Kr='Kreyall:BAAANQADCgQICAAAAA==.Kritea:BAAANQADCggIDwAAAA==.',
Ky='Kylva:BAAANQADCgIIAgAAAA==.Kyrís:BAABNQAECoEeAAICAAgKmAvnmQCyAQACAAgKmAvnmQCyAQAAAA==.Kyta:BAAANQAECgUIDAAAAA==.',
La='Laupess:BAAANQABCgIIAgAAAA==.',
Le='Lebron:BAAANQAECgIIBAAAAA==.',
Li='Lightbrew:BAAANQAECggICgAAAA==.Litmus:BAAANQADCgUIBQAAAA==.',
Lo='Locura:BAAANQADCggICQABNQAECggILAABAK0jAA==.',
['Là']='Làñçèñt:BAAANQADCgQJBQAAAA==.',
Ma='Madara:BAAANQAECgcIEwAAAA==.Magra:BAAANQABCgIIAgAAAA==.Makersmartun:BAAANQAECgMIBAAAAA==.Malthira:BAAANQAECgEIAQAAAA==.',
Mi='Milbi:BAAANQADCgUICQAAAA==.Minadette:BAAANQADCgYICQAAAA==.',
Ml='Mljr:BAAANQAECgQIBgAAAA==.',
Mo='Moira:BAAANQADCgcIBwAAAA==.Moloken:BAAANQADCgMIAwAAAA==.Movalon:BAABNQAECoEjAAIXAAkKcyH0FQAeAwAXAAkKcyH0FQAeAwAAAA==.',
My='Mymonk:BAAANQADCggJDgAAAA==.',
Na='Nativelock:BAAANQAECgUICgAAAA==.Nativéhunter:BAAANQADCgIIAgAAAA==.',
Ne='Nephilim:BAAANQAECgcIDgAAAA==.',
Ni='Nightresse:BAAANQAECgQIBAAAAA==.Nilrim:BAAANQABCgIIAgAAAA==.',
No='Nozomila:BAAANQAECgUIDgAAAA==.',
Ny='Nynnaeve:BAAANQAECgUICAAAAA==.',
On='Onthecoda:BAABNQAECoEhAAIKAAgKaSFVCgAIAwAKAAgKaSFVCgAIAwAAAA==.',
Oo='Oomgad:BAAANQADCgQIBAAAAA==.',
Op='Opani:BAAANQADCgIIAgAAAA==.',
Ot='Otisburgdk:BAAANQAECgEIAQAAAA==.',
Pa='Paeus:BAAANQABCgUICgAAAA==.Paigeturner:BAAANQAECgUIDwAAAA==.Palapets:BAAANQADCggIEAABNQAECggICAADAAAAAA==.Pantherarosa:BAAANQADCgQIBAABNQAECgUICgADAAAAAA==.Papalock:BAAANQAECgQICgABNQAECgcIFAAIAFkdAA==.Paramità:BAAANQABCgYICQAAAA==.Parenthi:BAAANQADCgEIAQAAAA==.Pazerp:BAAANQADCgEIAQAAAA==.',
Pe='Peaches:BAAANQADCgEIAQAAAA==.Persymphony:BAABNQAECoEdAAIXAAgKKR0AMQCpAgAXAAgKKR0AMQCpAgAAAA==.',
Ph='Phabio:BAAANQAECgUIBgAAAA==.Phlorps:BAAANQAECgUIBQABNQAFFAYIEgAOAFkPAA==.',
Pi='Pineappletea:BAAANQAECgUIEwAAAA==.Pinepally:BAAANQADCgQIBQAAAA==.Pinklock:BAAANQAECgUICgAAAA==.',
Po='Pockaidhealr:BAAANQAECgEIAQAAAA==.',
['Pø']='Pøøts:BAAANQAECgEIAQAAAA==.',
Qu='Quesy:BAAANQAFFAMIAwABNQAFFAQICAACAJkQAA==.',
Ra='Ragnapall:BAAANQADCgUIEAABNQAECgkJFwAEAMkaAA==.Ragnatotemzz:BAABNQAECoEXAAIEAAkKyRpXMwCGAgAEAAkKyRpXMwCGAgAAAA==.Ravenmoonray:BAAANQAECgEIAgAAAA==.Razivarus:BAAANQAECgEIAQAAAA==.',
Re='Rebelchild:BAAANQADCgcIHAABNQAECgEIAQADAAAAAA==.Redneckgirls:BAAANQADCgEJAQABNQAECgEIAQADAAAAAA==.Reimann:BAAANQADCgEIAQAAAA==.Rellock:BAAANQADCgcIBwABNQAECgEIAQADAAAAAA==.Renkari:BAAANQAECgIIAgAAAA==.Rennl:BAAANQAECgMIBAAAAA==.',
Ri='Rienix:BAAANQADCgYJDwAAAA==.Rihannon:BAAANQADCgUICAABNQAECgUICgADAAAAAA==.Ripsets:BAABNQAECoEsAAMFAAgKRSLHHAAKAwAFAAgKRSLHHAAKAwAYAAYKbxuwMQCWAQAAAA==.',
Ro='Rogueloki:BAABNQAECoEfAAMZAAkKgxSdIAC0AQAZAAYKvxSdIAC0AQAaAAUK1xGXTABEAQAAAA==.Rowscaris:BAAANQAECgUIBgAAAA==.',
Ry='Rynna:BAABNQAECoEUAAIIAAcKWR2fXwBPAgAIAAcKWR2fXwBPAgAAAA==.',
['Rä']='Rägnämagixx:BAAANQADCgYIEgABNQAECgkJFwAEAMkaAA==.',
Sa='Samelthund:BAAANQABCgUICQAAAA==.Sanxyn:BAAANQADCgYIBgAAAA==.Saraswati:BAAANQADCgEIAQAAAA==.Sarezen:BAAANQADCgYIFgAAAA==.Sarigos:BAAANQAECgYIEwAAAA==.',
Sc='Schieldemon:BAABNQAECoEsAAMMAAkKdhp2EADcAgAMAAkKdhp2EADcAgAUAAUKxQ2lTwAfAQAAAA==.Scrythe:BAABNQAECoEdAAILAAgKyBKKRgC/AQALAAgKyBKKRgC/AQAAAA==.Scynline:BAAANQADCgcICQAAAA==.Scynrine:BAAANQABCgIIAgAAAA==.',
Se='Selokra:BAAANQADCggIGAAAAA==.Selosi:BAAANQADCgYICQAAAA==.Selosine:BAAANQADCgYIBgAAAA==.Seseren:BAAANQADCgEIAQAAAA==.',
Sh='Shame:BAAANQADCgYIBgAAAA==.Sharrin:BAAANQADCgYJBgAAAA==.Shoran:BAAANQADCgYIBgAAAA==.',
Si='Silithus:BAAANQAECgEIAQAAAA==.',
Sl='Sleeptotem:BAAANQAECgQIBAAAAA==.Slime:BAAANQADCgMIAwAAAA==.',
So='Solomoon:BAABNQAECoEUAAIOAAYKZBxPVwDuAQAOAAYKZBxPVwDuAQAAAA==.Souleatr:BAAANQADCgEIAQABNQAECgYIEwADAAAAAA==.',
Sp='Speisgote:BAAANQAECgUICAAAAA==.',
St='Stalkurnjr:BAAANQADCgYIBwABNQAECgYIEwADAAAAAA==.Stealthpets:BAAANQADCggICQABNQAECggICAADAAAAAA==.Steelehorn:BAAANQADCgUIBQAAAA==.Stewpot:BAAANQADCgUIBQAAAA==.Stylish:BAABNQAECoEXAAQCAAkKtBA6egAHAgACAAkKFw86egAHAgAbAAIKqhgWLgCTAAAcAAEKHhHeKwA7AAAAAA==.',
Su='Suisui:BAAANQADCgcIGAAAAA==.Suling:BAAANQABCgIIAgAAAA==.Suunde:BAAANQADCgQIBAAAAA==.',
Sy='Sylathra:BAAANQABCgQIBAAAAA==.Syryn:BAAANQAECgUIBwAAAA==.',
Ta='Talasacerdos:BAAANQADCgcICQAAAA==.',
Th='Theelderlord:BAAANQADCgYIBgABNQAECgcIDgADAAAAAA==.Thorgrum:BAABNQAECoEdAAMdAAgKUSYSCgBaAwAdAAgKUSYSCgBaAwAQAAIKayGPaAC3AAAAAA==.Thûnderize:BAABNQAECoEfAAIEAAgKVht7NQB7AgAEAAgKVht7NQB7AgAAAA==.',
Ti='Tigolbittees:BAAANQADCggIDAAAAA==.Tillandra:BAAANQAECgQIBgAAAA==.Tirea:BAAANQAECgYIEwAAAA==.',
To='Toeppa:BAAANQADCgQIBAAAAA==.Toff:BAAANQADCgcIGQAAAA==.Toppâ:BAAANQADCgYIBgAAAA==.Totemish:BAAANQAECgUIBgAAAA==.',
Tr='Tripoloski:BAAANQAFFAIIAgAAAA==.',
Tu='Tugamuhpud:BAAANQAECgQICAAAAA==.',
Tz='Tzzird:BAABNQAECoEZAAIIAAgKlRvKUAB6AgAIAAgKlRvKUAB6AgAAAA==.',
Ug='Ugrah:BAAANQAECgYIDwAAAA==.',
Uk='Ukyomsi:BAAANQABCgIIAgABNQAECgYIEwADAAAAAA==.',
Un='Undeadheals:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
Va='Vagrant:BAAANQADCgQIBAAAAA==.Vairinia:BAAANQADCgQIBAAAAA==.Vawdkuh:BAABNQAECoEaAAIeAAgK8xOhNgAOAgAeAAgK8xOhNgAOAgAAAA==.',
Ve='Velddor:BAAANQAECgYIDgAAAA==.',
Vi='Vice:BAAANQAECgUIBQAAAA==.Vignette:BAAANQABCgUIBQAAAA==.',
Vo='Vodkantoast:BAAANQAECgUIDQAAAA==.',
Vy='Vyanna:BAAANQADCgIIAgAAAA==.Vytux:BAAANQABCgMIAwAAAA==.',
['Vö']='Vöx:BAAANQAECgUICAAAAA==.',
Wa='Wartrick:BAAANQAECgYIDgAAAA==.',
Wh='Whoudini:BAAANQAECgQICgAAAA==.',
Xe='Xerãth:BAABNQAECoEaAAISAAgKGwew8wB+AQASAAgKGwew8wB+AQAAAA==.',
Xi='Xiya:BAAANQAECgcICQAAAA==.',
Ya='Yarndog:BAAANQAECgIIAgAAAA==.Yarnell:BAAANQAECgMIBQAAAA==.Yaviel:BAAANQAECgUIBgAAAA==.',
Yu='Yushis:BAABNQAECoEdAAIMAAgKExpXGQB2AgAMAAgKExpXGQB2AgAAAA==.',
Za='Zarrgon:BAEBNQAECoEdAAMLAAkK/CE9HwCgAgALAAcKIyI9HwCgAgAdAAgKnhlsMwA6AgAAAA==.',
Ze='Zelderk:BAACNQAFFIEIAAMCAAQKmRBaFgAxAQACAAQKfRBaFgAxAQAcAAEK9wt6BQBCAAA1AAQKgSsAAwIACQrqIawZAEUDAAIACQpiIKwZAEUDABwAAgrfH0YeAKkAAAAA.Zeromus:BAAANQADCgcICwAAAA==.',
Zh='Zhenlim:BAAANQAECgIIAgAAAA==.',
Zo='Zoidbergg:BAAANQADCgEJAgABNQAECggIGQAIAJUbAA==.',
Zu='Zulraja:BAAANQADCgcIBwAAAA==.',
['Zÿ']='Zÿrä:BAAANQADCgEIAQAAAA==.',
['Àn']='Ànugra:BAAANQADCggIEgAAAA==.',
['Âl']='Âlpally:BAAANQADCgYIDAAAAA==.',
['Ðr']='Ðrizzt:BAAANQADCggICAABNQAECgYIEwADAAAAAA==.',
['ße']='ßellatrix:BAAANQAECgQIBQABNQAECgYIEwADAAAAAA==.',
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
