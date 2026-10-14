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

local lookup = {'Warrior-Arms','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','DemonHunter-Vengeance','Warlock-Affliction','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','Shaman-Elemental','Druid-Restoration','Paladin-Protection','DeathKnight-Blood','Mage-Frost','Hunter-BeastMastery','Hunter-Survival','Priest-Holy','Priest-Discipline','Unknown-Unknown','Druid-Guardian','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Enhancement','Evoker-Devastation','Druid-Balance','Paladin-Holy','Monk-Windwalker','Hunter-Marksmanship','Warrior-Protection','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aakier:BAABNQAECn9AAAIBAAkKIR1XMQD3AgABAAkKIR1XMQD3AgAAAA==.',
Ac='Acanda:BAAANQAFFAIIAgAAAA==.',
Ad='Aderai:BAAANQADCggICAAAAA==.Adolina:BAABNQAECn8yAAICAAkKfRyuMACcAgACAAkKfRyuMACcAgAAAA==.',
Ak='Akier:BAAANQAECgMIAwABNQAECgkJQAABACEdAA==.Akkier:BAAANQAECggICQABNQAECgkJQAABACEdAA==.',
Ap='Applebutter:BAAANQAECgEIAwAAAA==.',
As='Asmodeus:BAABNQAECn8ZAAMDAAkK0hoaGgCGAgADAAkK0hoaGgCGAgAEAAEK7AYWmQAoAAABNQAECgkJIQAFACEgAA==.Asuna:BAAANQAECgYIEAAAAA==.',
At='Atilia:BAAANQADCgQIBAABNQAECggIJAAGAOAhAA==.Atmosfear:BAAANQADCgQIBAAAAA==.',
Ax='Axeldar:BAAANQAECgYIBgAAAA==.',
Az='Azucena:BAAANQAECgEIAQAAAA==.',
Ba='Bananos:BAABNQAECn8pAAIHAAkKghwaAgAQAwAHAAkKghwaAgAQAwAAAA==.',
Be='Berrako:BAAANQADCgQIBAAAAA==.',
Bi='Billie:BAABNQAECn8aAAIIAAUK2wVLbwDrAAAIAAUK2wVLbwDrAAAAAA==.',
Bl='Blooddk:BAABNQAECn8qAAQHAAkKSyOOAACkAwAHAAkKCCOOAACkAwAJAAkKuR2BAwAKAwAKAAMKIgq8CAG0AAABNQAFFAYIEQALAEwdAA==.',
Bo='Boojum:BAAANQAECgcIEAAAAA==.Booze:BAAANQADCggIDQAAAA==.',
Ch='Chachisimo:BAABNQAECn8bAAILAAkKHyTfGABxAwALAAkKHyTfGABxAwAAAA==.Chivasaurus:BAAANQAECgIIAgABNQAFFAUICwAMAIYGAA==.',
Co='Covenant:BAAANQAECgUIBwAAAA==.',
Cr='Crunksmash:BAABNQAECn8dAAINAAkKPQ7rKADUAQANAAkKPQ7rKADUAQAAAA==.',
De='Demonbaked:BAAANQAECgIIAgABNQAFFAQICQAOAOoYAA==.Derpybômb:BAAANQADCgQIBAAAAA==.Dezyre:BAAANQAECgYIDwAAAA==.',
Di='Dillon:BAAANQAECgMIAwAAAA==.',
Do='Donlobö:BAAANQADCggIDQAAAA==.Dora:BAABNQAECn8fAAIPAAgKFBurKwBoAgAPAAgKFBurKwBoAgAAAA==.Dorim:BAAANQAECgEIAQAAAA==.',
El='Elmono:BAACNQAFFH8OAAMLAAUK/Q1XLQAdAQALAAQKJA1XLQAdAQAQAAEKrw9gEgBJAAA1AAQKfzcAAwsACQpXGwZ3AI8CAAsACQrsGQZ3AI8CABAABQodF6AdAP0AAAAA.Elohan:BAAANQAECgUIBQABNQAECgkJQAABACEdAA==.',
Er='Erther:BAAANQAECgcIDQAAAA==.',
Fa='Far:BAACNQAFFH8HAAIRAAUK3gmADwBbAQARAAUK3gmADwBbAQA1AAQKfywAAxEACQosG/YwANgCABEACQosG/YwANgCABIABQrdEFYLAD4BAAAA.',
Fe='Feral:BAAANQAECggICAAAAA==.Feralscale:BAAANQAECgIIAgAAAA==.',
Fl='Flashstep:BAAANQAECgYIDgAAAA==.',
Fo='Foofiqt:BAABNQAECn8dAAMTAAgKIiDEHQD4AgATAAgKIiDEHQD4AgAUAAMK+gyYGgCSAAAAAA==.Foxinahat:BAAANQADCgQIAgAAAA==.',
Fu='Fuddytotem:BAAANQAECgcIEgAAAA==.',
Fz='Fzy:BAAANQAECgEIAQABNQAECgcIEgAVAAAAAA==.Fzydin:BAAANQAECgEIAgABNQAECgcIEgAVAAAAAA==.',
Ge='Geus:BAAANQAECgQIBwAAAA==.',
Go='Goosejewce:BAABNQAECn8sAAMMAAkK9xxbGAA0AwAMAAkK9xxbGAA0AwACAAIKnBSV8ACEAAAAAA==.',
Gr='Gremmil:BAAANQADCgQIBAAAAA==.Grimscar:BAAANQAECgYIBgAAAA==.',
Gw='Gweg:BAACNQAFFH8GAAIRAAIKZBmdIACtAAARAAIKZBmdIACtAAA1AAQKfywAAhEACQrvIVwsAOcCABEACQrvIVwsAOcCAAAA.',
Ha='Hades:BAACNQAFFH8HAAIRAAUKBhnpCQCnAQARAAUKBhnpCQCnAQA1AAQKfzAAAhEACQrIIBIRAF0DABEACQrIIBIRAF0DAAAA.Halarda:BAACNQAFFH8NAAIRAAUKVhehCQCqAQARAAUKVhehCQCqAQA1AAQKfywAAhEACQr0H7koAPQCABEACQr0H7koAPQCAAAA.',
Ho='Hooves:BAACNQAFFH8UAAIWAAUKyAXeAwAPAQAWAAUKyAXeAwAPAQA1AAQKfzgAAhYACQqTGBMPAG0CABYACQqTGBMPAG0CAAAA.',
Ic='Icphunter:BAAANQADCggIBwAAAA==.',
Il='Ilythya:BAAANQADCgYIDwAAAA==.',
In='Infinus:BAAANQABCgUICQAAAA==.',
Is='Issolde:BAABNQAECn8YAAMXAAgKgRg/PgDMAQAXAAcKJBk/PgDMAQAYAAcK2Ba/WgChAQABNQADCgcICAAVAAAAAA==.',
Iz='Izthefoofi:BAAANQAECgEIAQABNQAECggIHQATACIgAA==.',
Ja='Jaelana:BAABNQAECn84AAMZAAgKvQkIGADjAQAZAAgKvQkIGADjAQACAAcKFA8yigBsAQAAAA==.Jazigor:BAAANQADCggIDwAAAA==.',
Jo='Josuboxxu:BAABNQAECn8lAAIaAAkKViFSAwByAwAaAAkKViFSAwByAwAAAA==.',
Ju='Judgyslap:BAAANQADCgUIBQAAAA==.',
Ka='Kamikozy:BAABNQAECn8+AAILAAkK4yN/CwCoAwALAAkK4yN/CwCoAwAAAA==.Kasharas:BAABNQAECn8dAAICAAcK6hOCdACqAQACAAcK6hOCdACqAQAAAA==.Kassandruh:BAAANQAECgYJCQAAAA==.Kazden:BAAANQAECgEIAQABNQAECgkJHQAbAKcRAA==.',
Kh='Khain:BAAANQADCggICAAAAA==.Khealer:BAABNQAECn8dAAITAAcKyhuYVQAfAgATAAcKyhuYVQAfAgAAAA==.',
Ki='Kindi:BAABNQAECn8ZAAMFAAcK3heAkgD6AQAFAAcK3heAkgD6AQAcAAUKaiCmbgDJAQAAAA==.Kitymeowmeow:BAACNQAFFH8UAAIdAAYKqSIWAwA6AgAdAAYKqSIWAwA6AgA1AAQKfzUAAh0ACQrJJTsCALsDAB0ACQrJJTsCALsDAAAA.',
Kl='Klausnomi:BAACNQAFFH8LAAIMAAUKhgYGEgBHAQAMAAUKhgYGEgBHAQA1AAQKfzcAAgwACQrgGKw6AIgCAAwACQrgGKw6AIgCAAAA.',
Ko='Korlo:BAAANQAECgEIAQABNQAECgUIBwAVAAAAAA==.Kowalzky:BAAANQADCgcIDQAAAA==.',
Kr='Krixer:BAAANQAECgEIAQAAAA==.',
['Kà']='Kàndin:BAABNQAECn8dAAIbAAkKpxEcNwAwAgAbAAkKpxEcNwAwAgAAAA==.',
La='Lamorak:BAABNQAECn8bAAIBAAkKMhlaTQCeAgABAAkKMhlaTQCeAgAAAA==.Lastdance:BAAANQAECgcIEQAAAA==.',
Li='Lilpsycho:BAAANQADCgQIBAAAAA==.',
Lo='Loldroodood:BAAANQADCgYIDwAAAA==.',
Lu='Lucia:BAAANQAECgUIEQAAAA==.',
Ma='Mafesto:BAAANQAECggIEgAAAA==.Magnusbane:BAAANQADCgIIAgABNQAECgIIAwAVAAAAAQ==.Malaqor:BAABNQAECn8kAAIGAAgK4CGMBQDQAgAGAAgK4CGMBQDQAgAAAA==.Manwe:BAAANQADCgQIBQAAAA==.Maylida:BAAANQADCgEIAQABNQAFFAYIEQALAEwdAA==.',
Mo='Monado:BAACNQAFFH8PAAMRAAUKDxhbCADAAQARAAUKDxhbCADAAQAeAAEK9AU7JQA+AAA1AAQKfxUAAxEACQpEHGA0AMwCABEACApMHWA0AMwCAB4ABArkE29MAPwAAAAA.Monkbluhd:BAAANQADCgQIBAAAAA==.Montedk:BAAANQAECgYIEgAAAA==.Moonjuice:BAABNQAECn8ZAAINAAgKoBNxJwDiAQANAAgKoBNxJwDiAQAAAA==.Moonlightt:BAAANQAECgIIAgAAAA==.Moosetameatu:BAABNQAECn8oAAIfAAgKgiPvBAAsAwAfAAgKgiPvBAAsAwAAAA==.Moscco:BAAANQADCgMIAwABNQAECgYIDgAVAAAAAA==.',
Na='Nahaii:BAAANQAECgMIBAABNQAFFAUIBwARAN4JAA==.Nakskao:BAAANQADCggICgABNQAFFAYIEQALAEwdAA==.',
Ne='Necrogenesis:BAABNQAECn8zAAQPAAkKLBroKwBmAgAPAAkKKhjoKwBmAgAYAAcKAhrnOAA+AgAXAAEKlArfqgAzAAAAAA==.Nelos:BAABNQAECn8rAAIgAAgKZh0BDgCfAgAgAAgKZh0BDgCfAgAAAA==.Neovisus:BAAANQADCgMIAwABNQAECgkJMwAPACwaAA==.',
Ni='Nineline:BAAANQADCgQIBAABNQAECgcIFwAhAMwjAA==.Nitroglycern:BAAANQAECgEIAQAAAA==.Nixhar:BAAANQAECgQIBAABNQAECgIIAwAVAAAAAQ==.',
No='Nothelping:BAAANQADCgUIBQAAAA==.',
Od='Odjinn:BAAANQABCgYIBgAAAA==.',
Pa='Parrudo:BAAANQAECgEIAQAAAA==.',
Pi='Pinkember:BAAANQADCgQIBAAAAA==.',
Po='Poisontips:BAAANQADCgUIBQAAAA==.',
Pr='Prettymu:BAAANQADCgEIAQAAAA==.',
Sa='Sadler:BAAANQADCgMIAwAAAA==.Sake:BAABNQAECn8XAAMYAAcK4R3XNABTAgAYAAcK4R3XNABTAgAXAAIK5wzFkwBnAAABNQADCggIDQAVAAAAAA==.Sakurá:BAAANQABCgMIAwABNQAECgUIBwAVAAAAAA==.Sanctu:BAABNQAECn8hAAMFAAkKISBDKwAYAwAFAAkKISBDKwAYAwAcAAIKjgn0BAFnAAAAAA==.',
Se='Setchyshock:BAAANQAECgQIBAAAAA==.',
Sh='Shulgin:BAABNQAECn8mAAIbAAkKaRs0IADIAgAbAAkKaRs0IADIAgAAAA==.',
Si='Silvia:BAAANQADCgUIBAAAAA==.',
Sk='Skankie:BAAANQAECgQIBQABNQAECggIGgAEABQdAA==.',
So='Sonari:BAAANQAECgYICgAAAA==.',
Su='Superspike:BAACNQAFFH8XAAIQAAYKIBh1AAD4AQAQAAYKIBh1AAD4AQA1AAQKfzQAAhAACQp0JDgBAIwDABAACQp0JDgBAIwDAAAA.Superspikee:BAAANQAECgEIAQABNQAFFAYIFwAQACAYAA==.Surlockedin:BAABNQAECn8fAAQHAAkKmBRkFQDxAAAKAAcKlRHLmQCgAQAHAAQKIBRkFQDxAAAJAAMKww9CRwCpAAAAAA==.',
Ta='Taekay:BAACNQAFFH8VAAIPAAYKTBw6BwDsAQAPAAYKTBw6BwDsAQA1AAQKfxYAAw8ACAoTI68eALoCAA8ACAoTI68eALoCABgABAowDGmbAMQAAAAA.Takamine:BAAANQAECgQIBQAAAA==.Talokan:BAAANQAECgIIAgABNQAECgUIBwAVAAAAAA==.',
Te='Teletubi:BAAANQAFFAIIAgAAAA==.',
Th='Thehunter:BAAANQADCgEIAQAAAA==.Thezoolander:BAAANQABCgIIBAAAAA==.',
Tu='Tullkas:BAAANQADCgEIAQAAAA==.',
Va='Vanillarista:BAACNQAFFH8HAAIiAAMKlxmEDgDlAAAiAAMKlxmEDgDlAAA1AAQKfx8AAiIACQobIYUPAPkCACIACQobIYUPAPkCAAAA.',
Ve='Vellara:BAAANQABCgIIAgAAAA==.',
Wa='Warmongering:BAAANQAECggIAQAAAA==.',
We='Wesdarian:BAAANQAECgIIAgAAAA==.',
Xi='Xirious:BAAANQAECgMIAwABNQAECgkJHwABAMEWAA==.',
Ze='Zero:BAABNQAECn8pAAIDAAkKth7RDwDxAgADAAkKth7RDwDxAgAAAA==.',
['Ís']='Ísolde:BAAANQADCgcICAAAAA==.',
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
