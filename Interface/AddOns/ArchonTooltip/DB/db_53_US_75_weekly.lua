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

local lookup = {'Unknown-Unknown','DeathKnight-Blood','Shaman-Elemental','Priest-Shadow','Priest-Holy','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Druid-Feral','Druid-Balance','Warrior-Arms','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Evoker-Preservation',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Adarris:BAAANQADCgMIAwAAAA==.',
Ae='Aelaria:BAAANQADCgYICwAAAA==.',
Ai='Aina:BAAANQABCgYIBwAAAA==.',
Al='Albz:BAAANQADCgUIBQAAAA==.Albzley:BAAANQADCgEIAQAAAA==.Albzu:BAAANQADCgYIBgAAAA==.Albzy:BAAANQAECgUIEAAAAA==.Aldien:BAAANQADCgEIAQAAAA==.Aleister:BAAANQAECgYIDAAAAA==.Alraka:BAAANQADCgYIBgAAAA==.',
An='Andylock:BAAANQADCgcIDQAAAA==.Anomali:BAAANQADCgcIDgAAAA==.',
Ar='Arcanism:BAAANQAECgYIBgAAAA==.Arteñ:BAAANQADCgcIBwAAAA==.',
As='Asrian:BAAANQAECgEIAQAAAA==.',
Au='Augment:BAEANQADCgcIAwABNQADCggIIwABAAAAAA==.',
Aw='Awo:BAAANQAECgIIAwABNQAFFAEIAQABAAAAAA==.',
Ay='Aylen:BAAANQAECgQIBwAAAA==.',
Az='Azera:BAAANQAECgYIEgAAAA==.',
Ba='Baaloroc:BAAANQADCgQIBAAAAA==.Babsvilla:BAAANQADCgYIEAAAAA==.Banegrim:BAAANQAECgUICwAAAA==.Barbararilla:BAAANQADCgUIBQAAAA==.Battlecat:BAAANQAECgcICwAAAA==.',
Bl='Blindwalker:BAABNQAECoEcAAICAAgKehykJAB6AgACAAgKehykJAB6AgAAAA==.',
Bo='Boudexcze:BAABNQAECoEmAAIDAAkKDhW8RgAvAgADAAkKDhW8RgAvAgAAAA==.',
Br='Bragdand:BAEANQADCggIIwAAAA==.Brawl:BAAANQAECgIIAgAAAA==.Brewfest:BAAANQAECgIIAwAAAA==.Brosk:BAAANQADCgMIAwAAAA==.',
Ca='Cadillacbob:BAAANQAECgYIEAAAAA==.Castigate:BAABNQAECoEoAAMEAAkK3CDrCgAhAwAEAAkK3CDrCgAhAwAFAAQKBh0fqQDfAAAAAA==.',
Ce='Celestiâl:BAAANQAECgMIBAAAAA==.',
Ch='Cheesemonk:BAAANQADCggIKgABNQAECggIJgAGAJclAA==.Cheesepally:BAABNQAECoEmAAMGAAgKlyVeEQBzAwAGAAgKlyVeEQBzAwAHAAEKciXoVgBWAAAAAA==.',
Co='Coolio:BAAANQADCgMIBQAAAA==.',
Cy='Cygnus:BAAANQADCgQIBAAAAA==.',
Da='Dalt:BAABNQAECoEzAAMGAAkKViFBJgASAwAGAAkKViFBJgASAwAIAAkK6xg5KgCmAgAAAA==.Dangauz:BAAANQAECggIEQAAAA==.Darnamus:BAAANQAECgMIAwAAAA==.Dartherd:BAAANQADCgcIBwAAAA==.Dawnotheholy:BAABNQAECoEdAAMHAAgK+xXvIQCmAQAGAAgKYQ+AlQDDAQAHAAcKgxXvIQCmAQAAAA==.',
De='Deathstar:BAACNQAFFIEUAAMJAAUKRhiXBQBoAQAJAAQKiRuXBQBoAQACAAEKOgszMAAnAAA1AAQKgSsAAwkACQoEIToMAB4DAAkACQoEIToMAB4DAAoABQrPFvllAFMBAAAA.Derregar:BAAANQADCgcIBwAAAA==.Detoks:BAAANQADCgEIAQAAAA==.Dezamius:BAAANQABCgMIAwABNQAECgkJLwALADkWAA==.',
Di='Dimir:BAAANQADCggICgAAAA==.Dingwang:BAAANQADCgcIBwABNQAECggIFwAMADMMAA==.',
Dk='Dkfatality:BAAANQAECgYIBgAAAA==.',
Do='Dominhoes:BAAANQAECgQIBQAAAA==.Dondon:BAAANQAECgUICgAAAA==.',
Dr='Dragnos:BAAANQABCgEIAQAAAA==.Drixe:BAAANQAECgEIAgAAAA==.Drogni:BAAANQADCgcIDQAAAA==.',
El='Electronvolt:BAAANQADCgUICQAAAA==.',
Eq='Equina:BAAANQADCgYIDAABNQAECgYIEgABAAAAAA==.',
Et='Ettle:BAABNQAECoEXAAIMAAgKMwzfCADVAQAMAAgKMwzfCADVAQAAAA==.',
Ez='Ezrai:BAAANQADCgUIBQAAAA==.',
Fa='Falilesta:BAAANQADCgcICgAAAA==.Fattwohander:BAAANQAECgIIAQAAAA==.',
Fe='Ferro:BAAANQADCggIHwAAAA==.',
Fr='Freya:BAAANQAECgQJBQAAAA==.Frostyqq:BAAANQAECgQIBQAAAA==.',
Ge='Geegnome:BAAANQABCgIIAgAAAA==.',
Gl='Gloomy:BAAANQAECgUIEAAAAA==.',
Gr='Grandcross:BAAANQADCgUIDAAAAA==.Grewkkaa:BAAANQADCgEIAQAAAA==.',
Gu='Gumbi:BAAANQAECgYICQAAAA==.Gumgum:BAABNQAECoEaAAIMAAgKdSW+AAB3AwAMAAgKdSW+AAB3AwAAAA==.Gumgumi:BAAANQAECgcICwAAAA==.',
Ha='Handelton:BAAANQAECgQIBAAAAA==.Hartun:BAAANQAECgMIAwAAAA==.Hashirama:BAABNQAECoEzAAMNAAkK9CTzAADOAwANAAkK1iTzAADOAwAOAAcKFCTTKABtAgAAAA==.Hasted:BAAANQAECgcIDwAAAA==.',
He='Heathledger:BAAANQADCgYIBgAAAA==.Hel:BAAANQADCgYIBgAAAA==.Hestia:BAAANQADCgQIBAAAAA==.',
Hr='Hrizul:BAAANQAECgUIDAAAAA==.',
Ib='Iblameheals:BAABNQAECoEaAAIPAAgK6A+/gAD2AQAPAAgK6A+/gAD2AQAAAA==.',
Il='Ilissa:BAAANQADCggIDwAAAA==.',
Im='Imaboomer:BAAANQADCgUICgAAAA==.',
Iz='Izoni:BAAANQAECgIIAgABNQAECggIGgAQAIQYAA==.',
Ja='Jagz:BAAANQAECgcIEAAAAA==.',
Ji='Jirachii:BAAANQAECgEIAQABNQAECggIHwAOAFoTAA==.',
Ka='Katamine:BAABNQAECoEbAAIOAAcKnQ+DSACcAQAOAAcKnQ+DSACcAQAAAA==.Katoz:BAAANQADCggIEgAAAA==.',
Ki='Killnall:BAAANQAECgUIDAAAAA==.Kirza:BAAANQABCgQIBAAAAA==.',
Kr='Krystarin:BAAANQAECgUIDAAAAA==.Kráytos:BAAANQAECgIIAwAAAA==.',
Kw='Kwan:BAAANQAECgIIAwAAAA==.',
La='Lateralus:BAABNQAECoEeAAIQAAgKVhkJDgBkAgAQAAgKVhkJDgBkAgAAAA==.Lazymage:BAAANQAECgMIBAAAAA==.',
Li='Liferips:BAAANQADCgYIBgAAAA==.Littlespells:BAAANQADCgcICwAAAA==.',
Lu='Lucifur:BAAANQADCggICAABNQAECggICAABAAAAAA==.Lutoo:BAAANQAECgYIDgAAAA==.',
Ma='Magog:BAAANQADCgcICwAAAA==.Malakaii:BAAANQADCggIEAAAAA==.Marajade:BAAANQADCgEIAQAAAA==.Masherkillu:BAABNQAECoEwAAIDAAkK+h5OGAAhAwADAAkK+h5OGAAhAwAAAA==.Masherpally:BAABNQAECoEfAAMGAAkKERExlADGAQAGAAkKtw0xlADGAQAHAAIKTR7+RwCkAAABNQAECgkJMAADAPoeAA==.Maxopjack:BAABNQAECoEaAAMRAAgKfBDCdADaAQARAAgKfBDCdADaAQASAAEKYwaOegArAAAAAA==.Maztajake:BAABNQAECoEXAAIOAAYKrSE6LQBOAgAOAAYKrSE6LQBOAgAAAA==.Maztashammy:BAAANQAECgQIBAABNQAECgYIFwAOAK0hAA==.Maztatroll:BAAANQAECgEIAQABNQAECgYIFwAOAK0hAA==.Mazzyjake:BAAANQAECgEIAQABNQAECgYIFwAOAK0hAA==.',
Me='Meadowlark:BAAANQADCgcIBwABNQAECggIFwATAHAGAA==.Medarah:BAAANQAECgIIAwAAAA==.Melchizedic:BAAANQADCgIIAgAAAA==.',
Mi='Mifune:BAAANQAECggICAAAAA==.',
Mo='Mordacity:BAEANQAECgUIEAAAAA==.',
['Mä']='Määt:BAAANQADCgIIAgAAAA==.',
Ne='Nelaras:BAAANQADCgEIAQAAAA==.Neàrro:BAAANQAECgYIEwAAAA==.',
Ni='Nightwing:BAAANQAECgQIBAAAAA==.Nissanaltima:BAAANQAECgQIBAAAAA==.',
No='Noahstewie:BAAANQADCgMIAwAAAA==.Nocturnüs:BAAANQAECgYIEAAAAA==.Nordikmage:BAAANQAECgUICgAAAA==.Noree:BAAANQAECgQIBQAAAA==.',
['Nê']='Nêcrömane:BAAANQADCgYICQAAAA==.',
Oh='Ohtheironey:BAAANQAECgEIAQAAAA==.Ohtheironi:BAAANQADCggIDAAAAA==.',
On='Ondereth:BAAANQAECgYIDgAAAA==.',
Pa='Palimorea:BAEANQADCgYIDAABNQADCggIIwABAAAAAA==.',
Pi='Piercey:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Pinkbubbly:BAAANQABCgEIAgABNQAECgkJKQAOALwSAA==.Pinkylove:BAABNQAECoEpAAIOAAkKvBIbNQAYAgAOAAkKvBIbNQAYAgAAAA==.',
Pr='Promathia:BAABNQAECoE6AAQGAAkK3SUQAwDfAwAGAAkK3SUQAwDfAwAHAAIKTBfpTgB9AAAIAAEKxiLX8ABjAAAAAA==.',
Pu='Puff:BAAANQAECgcIDQAAAA==.',
Qu='Quicksotaka:BAAANQABCgUIBQAAAA==.',
Ra='Raenori:BAAANQADCggICAAAAA==.Rangërdangër:BAABNQAECoEfAAIUAAgKIRb3UABUAgAUAAgKIRb3UABUAgAAAA==.Raptura:BAAANQADCgcIDgAAAA==.Razzki:BAAANQABCggIEwAAAA==.',
Re='Redrouges:BAABNQAECoExAAMVAAkKwyNtAgCpAwAVAAkKwyNtAgCpAwAWAAgKPRyAEQBWAgAAAA==.Redwood:BAAANQADCgYIBgAAAA==.Rekki:BAAANQADCgIIAgABNQAECgcIDAABAAAAAA==.Revhero:BAAANQAECgUIBgAAAA==.',
Rn='Rngcharge:BAAANQADCggIFQAAAA==.Rngdeath:BAAANQADCgYICQAAAA==.',
Ro='Rockchucker:BAAANQAECgcIEQAAAA==.Roman:BAAANQADCgcICwABNQADCgcIDgABAAAAAA==.Rotawnda:BAAANQADCgYIBgAAAA==.',
Ru='Runewolf:BAAANQABCgEIAgAAAA==.',
['Rï']='Rïas:BAAANQADCggICAAAAA==.',
Sa='Sathrelian:BAAANQAECgEIAQAAAA==.',
Sc='Scale:BAAANQADCgEIAQAAAA==.',
Se='Sekaiju:BAACNQAFFIEIAAQRAAQKOw40JwCdAAARAAIKAhQ0JwCdAAASAAEK5gWpHQBJAAAMAAEKAwuNDQBDAAA1AAQKgRwAAxEACArjH4wqAMICABEACArjH4wqAMICABIAAQoAGgxmAEoAAAAA.Selaera:BAAANQADCgcIDgAAAA==.',
Sh='Shadowbann:BAAANQAECgUIEwAAAA==.Shamwich:BAAANQAECgcICQAAAA==.Shankblue:BAAANQAECgcIBwABNQAECgcIDwABAAAAAA==.Shaori:BAAANQADCgQIBAAAAA==.Sharrise:BAAANQAECgMIAwAAAA==.Sheratan:BAAANQADCggIHwAAAA==.Shinzabansho:BAAANQADCggIGgAAAA==.Shortzo:BAABNQAECoExAAIXAAkK6ResBACkAgAXAAkK6ResBACkAgAAAA==.Shuchi:BAAANQAECgUIDQAAAA==.Shøcktherapy:BAAANQADCgcIBwAAAA==.',
Sk='Skeezicks:BAAANQADCgUIBQAAAA==.Skidoosh:BAAANQAECgEIAQAAAA==.',
Sl='Slippy:BAAANQADCggICAAAAA==.',
Sm='Smallwood:BAAANQADCgEIAQAAAA==.',
So='Sodastream:BAAANQADCgQIBQAAAA==.Sopheisty:BAAANQADCggICAAAAA==.',
Sq='Squigglybutt:BAAANQAECgYIEgAAAA==.Squishysam:BAAANQADCgYJCAAAAA==.',
Su='Sunfist:BAAANQADCgQJBAAAAA==.Sungchaluka:BAAANQADCgYICAAAAA==.',
Sy='Syntt:BAAANQADCggJCAAAAA==.',
Ta='Tailin:BAAANQABCgQIBAAAAA==.Tallaynia:BAAANQAECgcICgAAAA==.Talsomething:BAAANQAECgMIAwAAAA==.Talyn:BAAANQAECgQIBAABNQAECgYIEAABAAAAAA==.Tatsumâ:BAAANQAECgYIEgAAAA==.',
Th='Theironie:BAAANQADCgYIBgAAAA==.',
Ti='Ticus:BAEANQAECgQIBgAAAA==.',
Tl='Tlovexx:BAAANQAFFAIIAwAAAA==.',
To='Toews:BAAANQABCggICwAAAA==.Tolya:BAAANQAECgMIBQAAAA==.',
Tr='Tranqx:BAABNQAECoE1AAMJAAkK7SZ+AAD5AwAJAAkKsyZ+AAD5AwAKAAgKniaTBgCDAwAAAA==.Treva:BAABNQAECoEaAAIQAAgKhBixDwBBAgAQAAgKhBixDwBBAgAAAA==.Trizz:BAABNQAECoEtAAIYAAkKZySVBQCOAwAYAAkKZySVBQCOAwAAAA==.',
Tu='Tuts:BAAANQADCgIIAgAAAA==.',
Ty='Tythos:BAAANQAECgEIAQAAAA==.',
Uh='Uhnus:BAAANQADCgIIAwAAAA==.',
Um='Umbryss:BAAANQADCgQIBAAAAA==.',
Un='Undeadmans:BAAANQAECgEJAQAAAA==.Unhellios:BAAANQAECgMIAwAAAA==.',
Up='Uproar:BAABNQAECoEfAAIJAAkKYiPPBACEAwAJAAkKYiPPBACEAwAAAA==.',
Va='Vahlfi:BAAANQAECgYIBwABNQAFFAcIDgAVANMXAA==.Vale:BAAANQAECgUIDwAAAA==.',
Ve='Vekna:BAAANQADCgcIBwAAAA==.Vescovo:BAABNQAECoEbAAIFAAgKqyNrDwA2AwAFAAgKqyNrDwA2AwAAAA==.',
Wi='Wingback:BAAANQADCgYICAAAAA==.',
Wp='Wphoenix:BAAANQADCgUIAQAAAA==.',
Xh='Xhenshini:BAABNQAECoEvAAMLAAkKORavBQBdAgALAAkKCBSvBQBdAgAQAAgKqxUVEQAkAgAAAA==.',
Ye='Yeonguo:BAAANQAECgcIDAAAAA==.',
Za='Zalethe:BAAANQAECgcIEQAAAA==.Zary:BAAANQAECggIAgAAAA==.',
['Zê']='Zêdd:BAAANQADCgcIDwABNQAECggIIQAZAE4UAA==.',
['Zö']='Zöljin:BAAANQADCgUIBgAAAA==.',
['Ës']='Ësme:BAAANQADCgUIBQAAAA==.',
['Óð']='Óðin:BAAANQADCgQIBAAAAA==.',
['Üm']='Ümbra:BAAANQADCgYIBgAAAA==.',
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
