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

local lookup = {'Unknown-Unknown','Paladin-Holy','Shaman-Elemental','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Druid-Restoration','Druid-Feral','Mage-Arcane','DemonHunter-Havoc','Priest-Holy','Paladin-Retribution','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Survival','Paladin-Protection','Priest-Shadow','Rogue-Assassination','Warlock-Affliction',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Adiina:BAAANQADCgQIBQAAAA==.',
Ae='Aelera:BAAANQADCgMIAwAAAA==.',
Ah='Ahnkoh:BAAANQADCgYICQAAAA==.',
Ak='Ak:BAAANQADCgUIDQABNQABCgEIAQABAAAAAA==.',
Al='Alcool:BAAANQAECgMIAwAAAA==.Alindril:BAABNQAECn8uAAICAAkKgwx2GgCIAQACAAkKgwx2GgCIAQAAAA==.Alistarfall:BAAANQAECgQIBAABNQAECgkJHwADAAgPAA==.Alledra:BAAANQABCggICwAAAA==.Alyriana:BAABNQAECn8wAAQEAAkKjBNPEQBVAgAEAAkKmRJPEQBVAgADAAQK8RAB5ADPAAAFAAQKxwWM5gCdAAAAAA==.',
Am='Amiyo:BAAANQAECgEIAQAAAA==.',
Ar='Arylis:BAAANQADCgMIAwAAAA==.',
As='Asalamalikum:BAAANQAECgQIBQABNQAFFAQICwAGAKwhAA==.Ashfallen:BAAANQAECgIIBAAAAA==.',
At='Atpl:BAAANQAECgQIBAAAAA==.Atthegates:BAABNQAECn8pAAIHAAoKzg54SgAKAQAHAAoKzg54SgAKAQAAAA==.',
Az='Azrel:BAAANQAECgYIBgAAAA==.',
Ba='Bachira:BAAANQADCgMIAwAAAA==.Baddragon:BAACNQAFFH8QAAQIAAYKKhBLCAC6AQAIAAYKKhBLCAC6AQAJAAMKiBWkCADoAAAKAAIKUBoECQCdAAA1AAQKfyQABAkACgrjI/0EAEcDAAkACgrjI/0EAEcDAAgABQrHD38wABgBAAoAAwptH2IVANoAAAAA.Balboo:BAAANQAECgcICQABNQAFFAcIFQALAMIYAA==.Balto:BAACNQAFFH8VAAMLAAcKwhhjBwAXAgALAAYKXh5jBwAXAgAMAAMKgxHECwAGAQA1AAQKfzwABAsACgplJFwDAMgDAAsACgplJFwDAMgDAAwABApsEsFHAPYAAA0ABQqVJYMLAOcAAAAA.Bayleef:BAABNQAECn8qAAIMAAoKPhsHDwDkAgAMAAoKPhsHDwDkAgAAAA==.',
Bd='Bdragon:BAAANQADCgUIBQAAAA==.',
Be='Belac:BAABNQAECn8hAAIHAAoKnw+UiwD/AQAHAAoKnw+UiwD/AQAAAA==.Bemillion:BAAANQABCgIIAgAAAA==.Bettyboom:BAABNQAECn8tAAIOAAkKxhRQFQC/AQAOAAkKxhRQFQC/AQABNQABCgMIAwABAAAAAA==.',
Bo='Boorase:BAAANQAECgMIAwAAAA==.',
Br='Brewlaw:BAAANQADCgQIBwAAAA==.Brujita:BAAANQADCgIIAgAAAA==.Brèè:BAABNQAECn8wAAIPAAoK0B+ODwAmAwAPAAoK0B+ODwAmAwAAAA==.',
Bu='Bunny:BAABNQAECn8eAAIQAAoKKAwXMgA2AQAQAAoKKAwXMgA2AQAAAA==.',
Ca='Caelith:BAABNQAECn83AAIOAAkKyQ/5FgC1AQAOAAkKyQ/5FgC1AQAAAA==.Calrinara:BAAANQADCggIFgABNQAECggIDgABAAAAAA==.Cause:BAAANQAECgUIEQABNQAECgYIFwAOABgdAA==.',
Cl='Cl:BAAANQAECgEJAQABNQAECgoKIQAHAJ8PAA==.',
Co='Conall:BAACNQAFFH8IAAIRAAMKQgmaGwDLAAARAAMKQgmaGwDLAAA1AAQKfyQAAxEACgpBFr5kAG0CABEACgpBFr5kAG0CAAIAAQq/AR0wAScAAAAA.Confetti:BAABNQAECn8YAAIMAAgKXSG/DAACAwAMAAgKXSG/DAACAwAAAA==.',
Da='Daiquiri:BAAANQADCgUIBQABNQAECggIGAAMAF0hAA==.Dajova:BAAANQAECgcIBwAAAA==.Darling:BAAANQADCgIIAgAAAA==.',
Dd='Ddofpain:BAAANQADCgIIAgAAAA==.',
De='Deadmawheals:BAABNQAECn8bAAMLAAoKIQ+oFAA2AQALAAkKIQ+oFAA2AQASAAEKAADKaQAkAAAAAA==.Deathblooms:BAABNQAFFH8NAAIGAAcKfRADAwBXAQAGAAcKfRADAwBXAQAAAA==.Dermo:BAAANQAECgMIAwAAAA==.',
Di='Dimfate:BAAANQABCgYIBgAAAA==.',
Dm='Dmaw:BAABNQAECn8YAAQTAAcKCg6qPAAwAQATAAYKCg6qPAAwAQAUAAUKOBADLQADAQAVAAUKdgvoIADaAAAAAA==.',
Do='Doublmisting:BAAANQADCggICAAAAA==.',
Dr='Drarkbull:BAAANQAECggIEAAAAA==.Dreki:BAAANQADCgYIBgAAAA==.Drizzitt:BAAANQAECgIIAwAAAA==.',
Dy='Dyspeptic:BAAANQAECgIIAgABNQAFFAIICAARAK4KAA==.',
['Dó']='Dónkey:BAAANQADCggICAAAAA==.',
Eh='Ehunter:BAAANQADCgIIAgAAAA==.',
El='Electro:BAAANQAECgQIEQABNQAECgYIFwAOABgdAA==.Elementtamer:BAAANQADCgMIAwAAAA==.',
Es='Esh:BAABNQAECn8aAAMWAAkKqSIAGQAkAwAWAAgKuCEAGQAkAwAXAAIKQCX0OADdAAAAAA==.',
Ev='Evildarkness:BAAANQADCggICAAAAA==.Evilemt:BAAANQADCggICwAAAA==.Evilmt:BAAANQADCgYIBwAAAA==.',
Fa='Fappio:BAAANQAECgMIAwABNQAECgoKMAAIAKkfAA==.',
Fe='Fenlok:BAAANQADCgUIBQAAAA==.',
Fi='Firiana:BAAANQAECgUICQAAAA==.',
Fr='Frogsbreath:BAAANQADCgUIBQAAAA==.',
Ga='Galdrel:BAAANQADCgYIBwAAAA==.',
Gr='Greymist:BAAANQADCggICAAAAA==.Grimoire:BAAANQAECgMIAgAAAA==.',
Gu='Gullar:BAAANQAECgEIAQAAAA==.Guzzug:BAAANQADCgUIBQABNQAECggIFAAVANYRAA==.',
Ha='Hallsblack:BAAANQADCgIIAgAAAA==.Harami:BAAANQAECgEIAQABNQAECggIAwABAAAAAA==.Hartplate:BAAANQABCgUIBQAAAA==.Haymaker:BAABNQAECn8ZAAMGAAgKJRpwGAAnAQAGAAcKyRlwGAAnAQAYAAYKxA/8ggATAQAAAA==.',
He='Heide:BAAANQAECggIDgAAAA==.Helmon:BAAANQADCgIIAQAAAA==.',
Hi='Hizø:BAAANQAECgQIBQAAAA==.',
Ho='Ho:BAAANQAECgMIAwAAAA==.Hoofling:BAAANQAECgEIAQAAAA==.Hordeelf:BAAANQAECgIJAgAAAA==.Hordeforsure:BAACNQAFFH8RAAMZAAgKLRMHDAB+AQAZAAYKcxIHDAB+AQAaAAIKoRRlIwCmAAA1AAQKfygAAxkACgqPJM8GAGMDABkACgqPJM8GAGMDABoAAwrPIlkWAdYAAAE1AAQKAgkCAAEAAAAA.',
Hu='Humanwolf:BAAANQADCgMIBQAAAA==.',
Il='Iliyana:BAAANQAECgEIAQABNQAECgMIAQABAAAAAA==.',
In='Inovar:BAACNQAFFH8JAAIWAAMKLB2eHgAAAQAWAAMKLB2eHgAAAQA1AAQKfy8AAxYACgofJN4VADIDABYACgofJN4VADIDABcAAQonIwJiAGEAAAAA.',
Iz='Izugzug:BAACNQAFFH8LAAMGAAQKrCH8DgBlAQAGAAQKrCH8DgBlAQAbAAEKhwhkIAA9AAA1AAQKfysAAwYACgoDIUAIAHkDAAYACgoDIUAIAHkDABgABgoMEIx+ACIBAAAA.',
Je='Jefflewis:BAAANQABCgQIBAAAAA==.',
Jo='Joolam:BAAANQADCgQIBAAAAA==.',
Ju='Julibean:BAAANQAECgQIBAAAAA==.',
Jx='Jxyy:BAAANQADCgUIBQABNQAFFAQKDAAaAGEbAA==.',
Ka='Kaminey:BAAANQAECggIAwAAAA==.Karizev:BAAANQADCggICAAAAA==.',
Ke='Kekson:BAAANQAECgUIBQAAAA==.Keyoshe:BAAANQADCgIIAgAAAA==.',
Kh='Kheliyah:BAAANQAECgYIDgAAAA==.',
Ki='Kickinugget:BAAANQAECggIDwAAAA==.',
Ko='Korrkil:BAAANQADCgUIBQAAAA==.',
La='Lanthrastus:BAAANQAECgQIBgAAAA==.Largecaliber:BAAANQADCggICAAAAA==.',
Li='Liability:BAAANQADCgEIAQAAAA==.Lilac:BAAANQADCgIIAgAAAA==.Lirria:BAAANQABCgMIAwAAAA==.Lisanalgaib:BAABNQAECn8uAAIcAAkKyRBxDAD/AQAcAAkKyRBxDAD/AQAAAA==.',
Ly='Lynxxy:BAAANQAECgEIAQAAAA==.',
Ma='Magital:BAAANQAECggIDgABNQAECgoKKgAdAO4WAA==.Magnetic:BAAANQAECgIIAwABNQAECgYIFwAOABgdAA==.Manalorian:BAAANQADCgQIBAAAAA==.Maurita:BAAANQAECgQIBAAAAA==.',
Mc='Mcvoke:BAAANQABCgQIBQABNQABCgYICAABAAAAAA==.Mcwusseena:BAAANQABCgQIBQABNQABCgYICAABAAAAAA==.',
Me='Medalea:BAAANQABCgQIBgAAAA==.Medier:BAAANQADCgQIBAAAAA==.Menethel:BAAANQAECgYICgAAAA==.Meowjin:BAAANQADCggICAAAAA==.Meudail:BAAANQADCgIIAgAAAA==.',
Mi='Miah:BAAANQADCgEIAQAAAA==.Miasmata:BAABNQAECn8oAAIbAAgKdRttDgCSAQAbAAgKdRttDgCSAQAAAA==.Mikeoxlongg:BAAANQAECgEIAQABNQAECgcIFAAWALsJAA==.Missgrey:BAAANQADCgQIBAAAAA==.',
Mo='Mordaut:BAABNQAECn8aAAIOAAYKIB+nQQA5AQAOAAYKIB+nQQA5AQAAAA==.Morts:BAABNQAECn8jAAIFAAoKCxeeRgBHAgAFAAoKCxeeRgBHAgAAAA==.',
Mu='Muzuki:BAAANQAECgMIBAAAAA==.',
My='Mylaw:BAAANQADCgQICAAAAA==.',
Na='Nabi:BAAANQAECgYIEAABNQAECgYIEAABAAAAAA==.Naianasha:BAABNQAECn8fAAIKAAgKzwhMDgBiAQAKAAgKzwhMDgBiAQAAAA==.',
Ne='Neris:BAABNQAECn8dAAMMAAkKzRHtIwAGAgAMAAkKzRHtIwAGAgALAAMKSwohlgCAAAABNQAFFAMICQAWACwdAA==.',
No='Noggenkarl:BAAANQAECgYICQABNQAECgYICgABAAAAAA==.Nosfyrakktu:BAAANQAECgUICQABNQAECgkJHwADAAgPAA==.',
Nu='Nun:BAAANQAECgEIAQAAAA==.',
Ob='Obscur:BAAANQAECgcIDwAAAA==.',
On='Onepiece:BAAANQADCgEIAQABNQAFFAcIFQALAMIYAA==.',
Os='Osti:BAABNQAECn8yAAIeAAoKfSHyAACFAwAeAAoKfSHyAACFAwABNQAFFAIIBwATANMeAA==.',
Pa='Pahine:BAABNQAECn8dAAIEAAgKpw8mBQCuAQAEAAgKpw8mBQCuAQABNQAECggIAwABAAAAAA==.Pallywackèr:BAAANQAECgEIAQAAAA==.',
Pe='Pepedin:BAABNQAECn8gAAMfAAoKbQ4RGwC3AAARAAgKDQ9azgB+AQAfAAcKQQwRGwC3AAAAAA==.',
Ph='Phantoma:BAAANQADCgYIDAAAAA==.',
Pn='Pnkrweb:BAAANQAECgYIEQAAAA==.',
Po='Popshot:BAAANQAECgMIBAAAAA==.',
Pr='Preacharöund:BAAANQADCggICQAAAA==.Profit:BAABNQAECn8wAAMQAAoKaR0gJgDSAgAQAAoKaR0gJgDSAgAgAAYKmRrsLAC+AQAAAA==.',
Pu='Punduh:BAABNQAECn86AAIUAAoKlR+eAABxAwAUAAoKlR+eAABxAwAAAA==.',
Ra='Rabbidtotem:BAABNQAECn8YAAMDAAkKBRnbTABDAgADAAgKThnbTABDAgAFAAIKNgSfGwE1AAAAAA==.Rainquis:BAAANQABCgIIAgAAAA==.Rajabra:BAABNQAECn8nAAIhAAkKJBzJAwD/AQAhAAkKJBzJAwD/AQAAAA==.Rasoon:BAAANQADCgYIBgAAAA==.Raveroller:BAAANQAECgYICQAAAA==.',
Re='Redryder:BAAANQAECgQIBgAAAA==.Reevoke:BAABNQAFFH8KAAIJAAcKZxWjAQArAgAJAAcKZxWjAQArAgAAAA==.Reighven:BAAANQAECggIEAABNQAFFAQICwAGAKwhAA==.Rexson:BAABNQAECn8VAAIaAAcKpBAdNABVAQAaAAcKpBAdNABVAQAAAA==.',
Rh='Rhyderlight:BAAANQAECgIIAgAAAA==.Rhythm:BAABNQAECn8XAAIOAAYKGB3kjACsAAAOAAYKGB3kjACsAAAAAA==.',
Ro='Rola:BAAANQADCgUICQAAAA==.Rolla:BAAANQADCggIDgAAAA==.Romolus:BAAANQADCgYIBgAAAA==.',
Ru='Ruddertrim:BAABNQAECn8fAAMaAAoK2BauYABVAgAaAAoK2BauYABVAgAZAAcKaQ8OOQCIAQAAAA==.',
Sa='Sadist:BAAANQABCgIIAgAAAA==.Salinedione:BAAANQAECgQICgAAAA==.Sargeruas:BAAANQAECgEIAQAAAA==.',
Sc='Scottiiee:BAAANQADCggIFQAAAA==.Scratch:BAAANQADCgUIBwAAAA==.',
Se='Segen:BAABNQAECn8dAAIOAAkKxQp2yAD0AQAOAAkKxQp2yAD0AQAAAA==.Semip:BAAANQAECgIIBQAAAA==.Sen:BAABNQAECn8gAAMZAAoK/xVDDwAPAQAaAAUKUBn81gBSAQAZAAoK3xNDDwAPAQAAAA==.',
Sg='Sgttapeworm:BAAANQADCgEIAQAAAA==.',
Sh='Shacewoman:BAAANQAECgIIAgAAAA==.Shaitan:BAAANQADCgEIAQABNQAECggIAwABAAAAAA==.Sheeple:BAAANQADCgYIBgAAAA==.Shwah:BAAANQABCgQIBAAAAA==.Shîver:BAAANQAECgcICwAAAA==.',
Si='Sidearm:BAAANQAECgQIBAAAAA==.Silvane:BAAANQAECgMIAwAAAA==.',
Sk='Skaadooshh:BAAANQADCgUJCQABNQAFFAQICwAGAKwhAA==.',
Sl='Slayèr:BAAANQADCgYIBgAAAA==.',
Sn='Snaptraphunt:BAAANQADCgIIAgAAAA==.Snipedyou:BAAANQADCggIEgAAAA==.',
So='Sophie:BAAANQADCgIIAgAAAA==.',
St='Staberella:BAAANQADCgMIAwAAAA==.Stache:BAABNQAECn8YAAICAAoK6RZBCABBAgACAAoK6RZBCABBAgAAAA==.Stevethuzad:BAAANQAECgIIAgABNQAECggIFAAVANYRAA==.Stevo:BAAANQADCgYIDQAAAA==.Stormydaniel:BAAANQAECgcIDQAAAA==.',
Sy='Synikal:BAABNQAECn8qAAIFAAgKERNVLgApAQAFAAgKERNVLgApAQAAAA==.',
['Sâ']='Sâuron:BAAANQABCgcJCQAAAA==.',
['Sæ']='Sæ:BAAANQAECgIIAwAAAA==.',
Ta='Taleiran:BAABNQAECn8qAAIdAAoK7hZJGQCQAgAdAAoK7hZJGQCQAgAAAA==.',
Th='Thdro:BAAANQADCgYIBgAAAA==.Threeofseven:BAAANQADCgcICAAAAA==.Thrøat:BAABNQAECn8nAAIGAAoKSB5JGwDVAgAGAAoKSB5JGwDVAgAAAA==.',
Ti='Tiberiius:BAABNQAECn8fAAMaAAoKeRwfSACUAgAaAAoKeRwfSACUAgAZAAUKIRYJRAA4AQAAAA==.Tilly:BAABNQAECn8YAAIPAAcKuRXmOgDeAQAPAAcKuRXmOgDeAQAAAA==.Titus:BAAANQAECgYICwAAAA==.',
To='Toes:BAAANQADCgIIAgAAAA==.Toranny:BAAANQAECgEIAQAAAA==.',
Tr='Trigodun:BAAANQADCgYIBgAAAA==.',
Un='Undeadlysoul:BAABNQAECn8pAAQiAAkKpRx1CgDQAQAWAAkK/ht6VQBVAgAiAAYKnx11CgDQAQAXAAEKbhuYagBMAAAAAA==.Undedagaindk:BAACNQAFFH8bAAMYAAcKUCIRAgAyAgAYAAYKUCIRAgAyAgAGAAEKAACrOgAdAAA1AAQKfzIAAxgACgoaJosJAHIDABgACgoaJosJAHIDAAYAAQq+JRiwAGsAAAAA.',
Up='Uppercut:BAAANQAECgYICAAAAA==.',
Us='Ussford:BAABNQAECn8iAAQUAAgKsA6FJQBNAQAUAAcKaRCFJQBNAQAVAAYKZAY7JQCmAAATAAQKPwASggAEAAABNQAECgoKJwAWANcWAA==.Ussorlando:BAABNQAECn8nAAIWAAoK1xbfLgDLAgAWAAoK1xbfLgDLAgAAAA==.',
Va='Valaw:BAAANQADCggIGQAAAA==.Valgprincess:BAAANQADCgUIBQAAAA==.Vallaw:BAAANQADCggICQAAAA==.',
Vi='Vincentius:BAABNQAECn8ZAAIfAAcKAAkbFADoAAAfAAcKAAkbFADoAAAAAA==.',
Vo='Voidberg:BAAANQABCgYICAAAAA==.Voidflame:BAAANQAECgQICAAAAA==.Volteil:BAAANQADCgYIBgAAAA==.',
Vu='Vuori:BAABNQAECn8YAAMDAAcK5hh/pQBJAQADAAUKrhR/pQBJAQAFAAYKPx44NwAIAQAAAA==.',
Wa='Warstomp:BAAANQAECgMIBAAAAA==.',
We='Wetdog:BAAANQADCgIIAgABNQAFFAcIFQALAMIYAA==.',
Wh='Whixx:BAABNQAECn8eAAIWAAgKYwn4OgAaAQAWAAgKYwn4OgAaAQAAAA==.',
Wi='Wikm:BAAANQAECgUIBgAAAA==.Will:BAAANQAECgcIBwABNQAFFAQICgARABIhAA==.',
Xn='Xnaisa:BAABNQAECn8jAAIFAAoK8h/ABACfAgAFAAoK8h/ABACfAgAAAA==.',
Xp='Xplosive:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
Ys='Yshaarj:BAAANQADCgYICgABNQAECggIEgABAAAAAA==.',
Za='Zale:BAAANQAECgEIAQAAAA==.Zapey:BAAANQAECgcICwABNQAECggIHgAWAGMJAA==.',
Ze='Zerude:BAABNQAECn8qAAIIAAoK4BI3GAA5AgAIAAoK4BI3GAA5AgAAAA==.',
Zm='Zmr:BAABNQAECn8bAAMFAAkKMxzMOQB4AgAFAAkKMxzMOQB4AgADAAUKcx6UigCKAQAAAA==.Zmrr:BAAANQADCgIIAgABNQAECgkJGwAFADMcAA==.',
['Çh']='Çhris:BAAANQADCggIFQAAAA==.',
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
