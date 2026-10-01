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

local lookup = {'Monk-Windwalker','Unknown-Unknown','Shaman-Restoration','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Druid-Feral','Paladin-Holy','Priest-Holy','Warrior-Arms','DemonHunter-Devourer','DeathKnight-Frost','Shaman-Elemental','Mage-Frost','Mage-Arcane','Mage-Fire','Hunter-Survival','Warlock-Demonology','Druid-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Blood','Warrior-Fury',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aahhotep:BAAANQADCgQJBAAAAA==.',
Ai='Aitwa:BAAANQADCggICAAAAA==.',
Ak='Aksnowman:BAAANQADCgYICAAAAA==.',
Al='Aliane:BAAANQAECgQICAAAAA==.Almertato:BAAANQAECgQIBAAAAA==.Alydara:BAAANQAECgIIAwAAAA==.',
Am='Amoonday:BAAANQAECgEIAQAAAA==.',
An='Andes:BAAANQADCgcJCwAAAA==.',
Ar='Aramoonsong:BAABNQAECoEkAAIBAAgKHiFmDQDRAgABAAgKHiFmDQDRAgAAAA==.Aranrùth:BAAANQAECggIEwAAAA==.Arastellia:BAAANQADCgQJBQAAAA==.Aretria:BAAANQAECgEIAQAAAA==.Ariean:BAAANQADCggICQAAAA==.Arthin:BAAANQABCgQIBAAAAA==.',
Au='Auraborealis:BAAANQAECgQIBwAAAA==.',
Av='Avadon:BAAANQADCggICAAAAA==.Avarice:BAAANQAECgQIBwAAAA==.',
Az='Azuael:BAAANQAECgcIBwAAAA==.',
Ba='Ballzdragon:BAAANQAECgQIBAABNQAFFAIIAgACAAAAAA==.Balzamon:BAAANQAECgYIEgAAAA==.Bandgeek:BAAANQAECgYIEQAAAA==.',
Be='Beegood:BAAANQAECgUIEQAAAA==.Beweaver:BAAANQADCggICAABNQAECgQICAACAAAAAA==.',
Bi='Biebert:BAAANQAECgYIDgAAAA==.Bizzy:BAAANQADCgcIBwAAAA==.',
Bl='Blooddemon:BAAANQADCggICQABNQAECgcIGAADAGkaAA==.Bloodegg:BAABNQAECoEaAAIEAAgKSgu+YwD4AQAEAAgKSgu+YwD4AQAAAA==.',
Bo='Boinkadin:BAAANQADCgQIAgAAAA==.',
Br='Bradcrit:BAAANQAECgQIAgAAAA==.Braverecall:BAAANQADCgYICAAAAA==.Brewzlee:BAAANQAECgEIAgABNQAECggICAACAAAAAA==.Broomphondle:BAAANQAECgUICQAAAA==.Brootis:BAAANQADCgYIBQAAAA==.',
Bs='Bshoottu:BAAANQAECgQIDAAAAA==.',
Cd='Cdub:BAAANQADCgEIAQABNQAECgYIDQACAAAAAA==.',
Ce='Celexa:BAAANQADCgQIBwAAAA==.',
Ch='Chrisando:BAAANQABCgYIBwAAAA==.Chrisswamy:BAAANQABCgYIBwAAAA==.Chromesatan:BAAANQAECggIBQABNQAECggICAACAAAAAA==.',
Ci='Cityr:BAAANQADCgUIBQAAAA==.',
Cl='Cloud:BAAANQADCggJFwAAAA==.',
Cr='Crankypal:BAAANQABCgEIAQAAAA==.Cringevoker:BAAANQAECgEIAQAAAA==.',
Cw='Cwdcannabull:BAAANQADCgQIBAAAAA==.',
['Cá']='Cárl:BAAANQABCgIIAgAAAA==.',
Da='Daemage:BAAANQADCgQJBAAAAA==.Dagara:BAAANQADCgIJAgAAAA==.Darkdrittz:BAAANQAECgQIBwAAAA==.',
De='Deadash:BAAANQADCgcICwABNQAECgYIBwACAAAAAA==.Deathclaw:BAAANQAECgYIEAAAAA==.Deceptiõn:BAAANQABCgYIBgAAAA==.Deldúwath:BAAANQAECgUIDwAAAA==.Demigra:BAAANQABCgYICgAAAA==.Demontyllas:BAAANQADCgYIBgAAAA==.',
Di='Dionus:BAAANQAECgUIDAAAAA==.',
Do='Doanh:BAAANQABCgYICAAAAA==.Dolorquedura:BAAANQAECgEJAQAAAA==.Domoarigato:BAAANQAECgQICAAAAA==.',
Dr='Drakuluh:BAAANQADCgMIAwAAAA==.Drapaco:BAAANQABCgMIAwAAAA==.Draucan:BAAANQAECgcIEwAAAA==.Dreadmoor:BAAANQADCgQJBgABNQAECgQIDgACAAAAAA==.Dribblesnot:BAAANQAECgQIDgAAAA==.Driden:BAAANQAECgYICAAAAA==.',
Dy='Dya:BAAANQADCgcIBwAAAA==.',
Ec='Echolock:BAAANQAECgIIAgAAAA==.',
El='Elementálist:BAAANQADCgUIBgABNQADCggJDgACAAAAAA==.Elemetzy:BAAANQAECgQIBgAAAA==.Elkul:BAAANQAECgQICQAAAA==.Elsoned:BAAANQAECgEIAwAAAA==.',
Ev='Evokyn:BAAANQADCgEIAQAAAA==.',
Fa='Falafel:BAABNQAECoEUAAIFAAYKmRKXmQCCAQAFAAYKmRKXmQCCAQAAAA==.Fattaco:BAABNQAECoEYAAIDAAcKaRojQwAHAgADAAcKaRojQwAHAgAAAA==.',
Fl='Floss:BAAANQAECgQIBwAAAA==.Flubb:BAAANQAECgcIEwAAAA==.Flígbot:BAAANQAECggICAAAAA==.',
Fo='Fofglass:BAAANQADCgEIAQABNQAECggIGwACAAAAAA==.Followmenot:BAAANQAECgYIDwAAAA==.Fortbuff:BAAANQAECggIEAAAAA==.',
Fr='Frostyballz:BAAANQADCggICAABNQAECgYIDwACAAAAAA==.Frëyæ:BAAANQADCgQIBAABNQAFFAIIAgACAAAAAA==.',
Fu='Furgus:BAAANQADCgYJCwABNQAECgMIBQACAAAAAA==.',
Fy='Fyerflise:BAAANQADCgUICQAAAA==.Fyrakkobama:BAEANQADCgYIBwABNQAECgkJFgAGACUdAA==.',
Ga='Gannador:BAAANQADCgEIAQAAAA==.',
Gg='Ggreed:BAAANQADCgEIAQAAAA==.',
Go='Gobblegobble:BAAANQAECgYIDwAAAA==.Gosudizzle:BAABNQAECoEcAAIEAAkK/SFnDgBKAwAEAAkK/SFnDgBKAwABNQAECgYIDQACAAAAAA==.',
Gr='Grippingtaco:BAAANQADCgYIBgABNQAECgcIGAADAGkaAA==.',
Gu='Gulldarilynn:BAAANQAECgIIAwAAAA==.',
Gw='Gwendolyn:BAABNQAECoEcAAIHAAgK/SEoBAAJAwAHAAgK/SEoBAAJAwABNQAECggIJAABAB4hAA==.',
Ha='Hakubell:BAACNQAFFIEHAAIIAAMK1h1LDQARAQAIAAMK1h1LDQARAQA1AAQKgSoAAwgACQoTJUECAL8DAAgACQoTJUECAL8DAAUABQp1INuEALcBAAE1AAQKBggUAAkAZBwA.Hammershock:BAAANQAECgMICgAAAA==.Hasdiel:BAAANQAECgUJDQAAAA==.',
He='Heartim:BAAANQADCgQIBAAAAA==.Heädaches:BAAANQAECgMIBAAAAA==.',
Ho='Holynuke:BAAANQADCgcIBwABNQAFFAQICAAKAJkQAA==.',
Il='Illimommy:BAACNQAFFIESAAILAAcKWRVOAQBsAgALAAcKWRVOAQBsAgA1AAQKgRkAAgsACQoKIOwMAPYCAAsACQoKIOwMAPYCAAAA.',
In='Inkarok:BAAANQAECgQICQAAAA==.',
Is='Ishkode:BAAANQAECgcIEgAAAA==.',
It='Itachi:BAAANQAECgEIAQAAAA==.',
Ja='Jalapeno:BAAANQAECgQIBwAAAA==.Jami:BAABNQAECoEWAAIMAAgKZg+gLgDGAQAMAAgKZg+gLgDGAQABNQADCgIJAgACAAAAAA==.',
Je='Jellybean:BAAANQADCggIFwAAAA==.',
Ji='Jitlo:BAACNQAFFIENAAINAAYK9QzABADiAQANAAYK9QzABADiAQA1AAQKgSYAAg0ACQrbIYIPAFIDAA0ACQrbIYIPAFIDAAAA.Jitsham:BAAANQAECgYJBgAAAA==.',
Jo='Joesa:BAAANQAECgIIAgAAAA==.',
Ka='Kalanrahl:BAABNQAECoEaAAQOAAgKkxQZCAAVAgAOAAgKkxQZCAAVAgAPAAYKUgpi9ABQAQAQAAEK1ANcCwArAAAAAA==.Kaldenormu:BAAANQADCgQJBAAAAA==.',
Ke='Kemaneral:BAAANQADCgIJAgAAAA==.',
Kh='Khaiduus:BAAANQAECgUIDAAAAA==.',
Ki='Killatroll:BAAANQADCgEIAQAAAA==.Kilmonger:BAAANQADCgQJBQAAAA==.Kirinkurai:BAAANQAECgYIEgAAAA==.Kittsune:BAAANQADCgYIBgAAAA==.Kizmet:BAAANQAECgIJBQAAAA==.',
Km='Kmoniwnaleya:BAAANQADCggIDgAAAA==.',
Ko='Kottenmouth:BAABNQAECoEqAAIRAAkKsh9pAQA9AwARAAkKsh9pAQA9AwAAAA==.',
Kr='Kreyall:BAAANQADCgQJBQAAAA==.Kritea:BAAANQADCggIDwAAAA==.',
Ky='Kylva:BAAANQADCgIIAgAAAA==.Kyrís:BAABNQAECoEXAAIKAAcKTgyFlgCFAQAKAAcKTgyFlgCFAQAAAA==.Kyta:BAAANQAECgQIBwAAAA==.',
Le='Lebron:BAAANQAECgIIBAAAAA==.',
Li='Lightbrew:BAAANQAECggICAAAAA==.',
['Là']='Làñçèñt:BAAANQADCgQJBQAAAA==.',
Ma='Madara:BAAANQAECgUIDAAAAA==.Magra:BAAANQABCgIIAgAAAA==.Makersmartun:BAAANQAECgEIAQAAAA==.Malthira:BAAANQAECgEIAQAAAA==.',
Mi='Milbi:BAAANQADCgUIBQAAAA==.Minadette:BAAANQADCgMIAwAAAA==.',
Ml='Mljr:BAAANQAECgIIAgAAAA==.',
Mo='Moira:BAAANQADCgYJBgAAAA==.Moloken:BAAANQADCgMIAwAAAA==.Movalon:BAABNQAECoEfAAISAAkKsiBDFgAEAwASAAkKsiBDFgAEAwAAAA==.',
My='Mymonk:BAAANQADCggJDgAAAA==.',
Na='Nativelock:BAAANQAECgUICQAAAA==.Nativéhunter:BAAANQADCgIIAgAAAA==.',
Ne='Nephilim:BAAANQAECgYIDAAAAA==.',
Ni='Nightresse:BAAANQAECgQIBAAAAA==.',
No='Nozomila:BAAANQAECgUIDAAAAA==.',
Ny='Nynnaeve:BAAANQAECgIIAwAAAA==.',
On='Onthecoda:BAABNQAECoEaAAITAAcKkiKdDgCxAgATAAcKkiKdDgCxAgAAAA==.',
Oo='Oomgad:BAAANQADCgQIBAAAAA==.',
Op='Opani:BAAANQADCgIIAgAAAA==.',
Ot='Otisburgdk:BAAANQAECgEIAQAAAA==.',
Pa='Paeus:BAAANQABCgUICgAAAA==.Paigeturner:BAAANQAECgQICgAAAA==.Palapets:BAAANQADCggIEAABNQADCggICQACAAAAAA==.Pantherarosa:BAAANQADCgQIBAABNQAECgMIBQACAAAAAA==.Papalock:BAAANQAECgQIBgABNQAECgYIDwACAAAAAA==.Parenthi:BAAANQADCgEIAQAAAA==.',
Pe='Persymphony:BAAANQAECgcIEwAAAA==.',
Ph='Phabio:BAAANQAECgUIBgAAAA==.Phlorps:BAAANQAECgUIBQABNQAFFAUIDgAJAOsOAA==.',
Pi='Pineappletea:BAAANQAECgUIEwAAAA==.Pinepally:BAAANQADCgQIBQAAAA==.Pinklock:BAAANQAECgMIBQAAAA==.',
Po='Pockaidhealr:BAAANQAECgEIAQAAAA==.',
['Pø']='Pøøts:BAAANQABCgIIAgAAAA==.',
Qu='Quesy:BAAANQAECggICwABNQAFFAQICAAKAJkQAA==.',
Ra='Ragnapall:BAAANQADCgUIEAABNQAFFAIIAgACAAAAAA==.Ragnatotemzz:BAAANQAFFAIIAgAAAA==.Ravenmoonray:BAAANQAECgEIAgAAAA==.Razivarus:BAAANQAECgEIAQAAAA==.',
Re='Rebelchild:BAAANQADCgcIHAABNQAECgEIAQACAAAAAA==.Redneckgirls:BAAANQADCgEJAQABNQAECgEIAQACAAAAAA==.Reimann:BAAANQADCgEIAQAAAA==.Renkari:BAAANQADCggIHAAAAA==.Rennl:BAAANQAECgEIAQAAAA==.',
Ri='Rienix:BAAANQADCgYJDwAAAA==.Rihannon:BAAANQADCgUICAABNQAECgMIBQACAAAAAA==.Ripsets:BAABNQAECoElAAMEAAgKiyGzGwD2AgAEAAgKiyGzGwD2AgAUAAYKbxthKgCnAQAAAA==.',
Ro='Rogueloki:BAABNQAECoEaAAMVAAkKexM8HwCvAQAVAAYKMxM8HwCvAQAWAAUK1xG2PgBJAQAAAA==.Rowscaris:BAAANQAECgEJAQAAAA==.',
Ry='Rynna:BAAANQAECgYIDwAAAA==.',
['Rä']='Rägnämagixx:BAAANQADCgYIEgABNQAFFAIIAgACAAAAAA==.',
Sa='Sanxyn:BAAANQADCgYIBgAAAA==.Saraswati:BAAANQADCgEIAQAAAA==.Sarezen:BAAANQADCgYIEAAAAA==.Sarigos:BAAANQAECgUIDgAAAA==.',
Sc='Schieldemon:BAABNQAECoEjAAILAAgKUxgUFgCDAgALAAgKUxgUFgCDAgAAAA==.Scrythe:BAAANQAECgcIEwAAAA==.Scynline:BAAANQADCgcICQAAAA==.Scynrine:BAAANQABCgIIAgAAAA==.',
Se='Selokra:BAAANQADCggIGAAAAA==.Selosi:BAAANQADCgYICQAAAA==.Selosine:BAAANQADCgYIBgAAAA==.Seseren:BAAANQADCgEIAQAAAA==.',
Sh='Shame:BAAANQADCgYIBgAAAA==.Sharrin:BAAANQADCgYJBgABNQAECgUICAACAAAAAA==.',
Si='Silithus:BAAANQAECgEIAQAAAA==.',
Sl='Sleeptotem:BAAANQAECgQIBAAAAA==.Slime:BAAANQADCgMIAwAAAA==.',
So='Solomoon:BAABNQAECoEUAAIJAAYKZBxBSQD5AQAJAAYKZBxBSQD5AQAAAA==.Souleatr:BAAANQADCgEIAQABNQAECgYJDwACAAAAAA==.',
Sp='Speisgote:BAAANQAECgIIAwAAAA==.',
St='Stalkurnjr:BAAANQADCgYIBwABNQAECgUIDgACAAAAAA==.Stealthpets:BAAANQADCggICQABNQADCggICQACAAAAAA==.Steelehorn:BAAANQADCgUIBQAAAA==.Stewpot:BAAANQADCgUIBQAAAA==.Stylish:BAAANQAECggIEgAAAA==.',
Su='Suisui:BAAANQADCgcIGAAAAA==.Suunde:BAAANQADCgQIBAAAAA==.',
Sy='Sylathra:BAAANQABCgQIBAAAAA==.Syryn:BAAANQAECgQIBAAAAA==.',
Ta='Talasacerdos:BAAANQADCgcICQAAAA==.',
Th='Theelderlord:BAAANQADCgYIBgABNQAECgYIDAACAAAAAA==.Thorgrum:BAAANQAECgcIEwAAAA==.Thûnderize:BAAANQAECgYIEwAAAA==.',
Ti='Tigolbittees:BAAANQADCggIDAAAAA==.Tillandra:BAAANQAECgIIAgAAAA==.Tirea:BAAANQAECgYJDwAAAA==.',
To='Toeppa:BAAANQADCgQIBAAAAA==.Toff:BAAANQADCgYIEgAAAA==.Toppâ:BAAANQADCgYIBgAAAA==.Totemish:BAAANQAECgUIBgAAAA==.',
Tr='Tripoloski:BAAANQAFFAIIAgAAAA==.',
Tu='Tugamuhpud:BAAANQADCgIIAgAAAA==.',
Tz='Tzzird:BAAANQAECgUJDgAAAA==.',
Ug='Ugrah:BAAANQAECgUICQAAAA==.',
Uk='Ukyomsi:BAAANQABCgIIAgABNQAECgYJDwACAAAAAA==.',
Un='Undeadheals:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.',
Va='Vagrant:BAAANQADCgQIBAAAAA==.Vairinia:BAAANQADCgQIBAAAAA==.Vawdkuh:BAAANQAECgcIDwAAAA==.',
Ve='Velddor:BAAANQAECgUICAAAAA==.',
Vi='Vice:BAAANQAECgUIBQAAAA==.',
Vo='Vodkantoast:BAAANQAECgUIDQAAAA==.',
Vy='Vyanna:BAAANQADCgIIAgAAAA==.Vytux:BAAANQABCgMIAwAAAA==.',
['Vö']='Vöx:BAAANQAECgMIAwAAAA==.',
Wa='Wartrick:BAAANQAECgUICAAAAA==.',
Wh='Whoudini:BAAANQAECgMIBgAAAA==.',
Xe='Xerãth:BAAANQAECgYIEAAAAA==.',
Xi='Xiya:BAAANQAECgIIAgAAAA==.',
Ya='Yarndog:BAAANQADCgYIFAAAAA==.Yarnell:BAAANQAECgEIAgAAAA==.Yaviel:BAAANQAECgUIBgAAAA==.',
Yu='Yushis:BAAANQAECgcIEwAAAA==.',
Za='Zarrgon:BAEBNQAECoEWAAMGAAkKJR0OIwBrAgAGAAgKnhkOIwBrAgAXAAUKwSIKOgDdAQAAAA==.',
Ze='Zelderk:BAACNQAFFIEIAAMKAAQKmRA5EQAzAQAKAAQKfRA5EQAzAQAYAAEK9wtvBABCAAA1AAQKgSkAAwoACQpuIWUWAEYDAAoACQrmH2UWAEYDABgAAgrfHyoaAK0AAAAA.Zeromus:BAAANQADCgcICwAAAA==.',
Zh='Zhenlim:BAAANQAECgIIAgAAAA==.',
Zo='Zoidbergg:BAAANQADCgEJAgABNQAECgUJDgACAAAAAA==.',
Zu='Zulraja:BAAANQADCgcIBwAAAA==.',
['Zÿ']='Zÿrä:BAAANQADCgEIAQAAAA==.',
['Àn']='Ànugra:BAAANQADCggICgAAAA==.',
['Âl']='Âlpally:BAAANQADCgYIDAAAAA==.',
['ße']='ßellatrix:BAAANQAECgQIBQABNQAECgYJDwACAAAAAA==.',
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
