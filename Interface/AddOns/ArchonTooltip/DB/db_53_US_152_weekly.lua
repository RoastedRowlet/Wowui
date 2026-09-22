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

local lookup = {'DemonHunter-Havoc','Warlock-Demonology','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Warrior-Arms','Shaman-Enhancement','Mage-Arcane','Paladin-Holy','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Hunter-Marksmanship','Priest-Discipline','DeathKnight-Frost','Druid-Balance','Warrior-Fury','Priest-Holy','Warlock-Affliction','Paladin-Protection','Druid-Restoration','Druid-Guardian','Priest-Shadow',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaylasecura:BAABNQAECoEYAAIBAAgKgRtIGwBKAgABAAgKgRtIGwBKAgAAAA==.',
Ab='Abelladanger:BAAANQADCgQJBAAAAA==.Abracadavar:BAAANQADCgEIAQABNQAFFAYJEgACAGAfAA==.Absinth:BAABNQAECoEUAAIDAAcKkQxlSABjAQADAAcKkQxlSABjAQAAAA==.',
Ai='Aidaric:BAAANQADCgUJBQAAAA==.Airfriend:BAABNQAECoEcAAMEAAgKAgvmVQCSAQAEAAgKAgvmVQCSAQAFAAUKXhutWwCGAQAAAA==.',
Al='Alder:BAAANQAECgQIBAAAAA==.Alphard:BAAANQAECgYJDgAAAA==.',
An='Anelowyn:BAAANQAECgYJDgAAAA==.Angrychicken:BAAANQADCgMIAwAAAA==.',
Ap='Apocal:BAABNQAECoEeAAIGAAkKayLpAACDAwAGAAkKayLpAACDAwAAAA==.',
Ar='Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAAANQAECgIJAgAAAA==.Asmozaps:BAAANQAECgUJCQAAAA==.',
Az='Aziel:BAAANQAECgYICwAAAA==.Azmodeaus:BAAANQADCgcIBwAAAA==.',
Ba='Baraden:BAAANQAECgcICwAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQADCgYICgAAAA==.Bih:BAAANQADCgMIAwAAAA==.Billiards:BAAANQADCggICAABNQAECgcIEQAHAAAAAA==.Birgetta:BAAANQADCggICAABNQAECggIFQABAB0DAA==.',
Bl='Blorne:BAAANQAECgQICAAAAA==.',
Bo='Bobodaklown:BAABNQAECoEVAAIIAAcKHxpVVQADAgAIAAcKHxpVVQADAgAAAA==.Boombawks:BAAANQADCgUICQAAAA==.Boomnbrew:BAABNQAECoEYAAIJAAcKawp6EQBZAQAJAAcKawp6EQBZAQAAAA==.Bownir:BAAANQAECgUICgAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAABNQAECoEbAAMKAAgKrxJRGAD6AQAKAAgKrxJRGAD6AQALAAMKKBAEJwC5AAAAAA==.',
Bu='Bubonic:BAAANQAECgUJCQAAAA==.Buenasalud:BAAANQAECgQICAAAAA==.',
Ca='Caylea:BAABNQAECoEfAAIMAAkKjx2CJADhAgAMAAkKjx2CJADhAgAAAA==.',
Ch='Chalis:BAAANQAECgQICwAAAA==.',
Cl='Clamsquirter:BAABNQAECoEUAAMEAAcKTh0BKgBaAgAEAAcKTh0BKgBaAgANAAIKtQkQIQB+AAAAAA==.',
Co='Coldhwip:BAAANQAECgcIEwAAAA==.',
Cr='Crash:BAABNQAECoEgAAIMAAkKgBqvLwCrAgAMAAkKgBqvLwCrAgAAAA==.Crtaker:BAAANQAECgcICAAAAA==.Crysis:BAAANQAECgcJEwAAAA==.',
Cu='Cuahtemoc:BAAANQADCgQJBwAAAA==.',
Da='Dabss:BAAANQAECgEIAQAAAA==.Daelin:BAAANQAECgYJDgAAAA==.Dagda:BAAANQAECgEIAQAAAA==.Danye:BAAANQAECgIJAwAAAA==.Darkscout:BAAANQADCgUJDwAAAA==.',
De='Decease:BAAANQAECgQIBAABNQAECgkJGQACAMYfAA==.Delium:BAACNQAFFIEGAAIOAAQKohFgEQBQAQAOAAQKohFgEQBQAQA1AAQKgR8AAg4ACQq8IaAcAEUDAA4ACQq8IaAcAEUDAAAA.Demonmommy:BAAANQAECgQIBAAAAA==.Deäthrose:BAABNQAECoEbAAMFAAgKbg/8QQDtAQAFAAgKbg/8QQDtAQAEAAcKoAldaABRAQAAAA==.',
Di='Die:BAAANQAECgYICQAAAA==.Diegoo:BAAANQADCgUIBQAAAA==.Disc:BAAANQADCgQIBgAAAA==.',
Do='Doadin:BAABNQAECoEVAAIPAAcKIxePPgD8AQAPAAcKIxePPgD8AQAAAA==.Doominatrix:BAABNQAECoEXAAICAAcKrBIzVQDNAQACAAcKrBIzVQDNAQAAAA==.Dotem:BAAANQADCgYICgAAAA==.',
Dr='Dreadraven:BAAANQADCgYIDAAAAA==.Drip:BAAANQAECgIIAgAAAA==.Druidhams:BAAANQAECgcIDQAAAA==.',
Du='Dunktars:BAABNQAECoEXAAIMAAcKmSB0PwBoAgAMAAcKmSB0PwBoAgAAAA==.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBgAAAA==.',
Ei='Eightball:BAAANQADCggIFgABNQAECgcIEQAHAAAAAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBgAHAAAAAA==.Elisha:BAABNQAECoExAAIIAAgK7A+9XgDjAQAIAAgK7A+9XgDjAQAAAA==.',
Er='Erebostro:BAAANQAECgYJDgAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgMIBAAAAA==.Fauxphoe:BAAANQADCgMIAwAAAA==.Fauxtotem:BAABNQAECoEbAAINAAgKYhzFBwCzAgANAAgKYhzFBwCzAgAAAA==.',
Fe='Fender:BAAANQAECgEIAQAAAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAABNQAECoEcAAMCAAgKhyKbMQBYAgACAAYKryObMQBYAgAQAAIKDR9SPQCoAAAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.Flush:BAAANQAECggICAAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAFFAIIAgAHAAAAAA==.',
Fu='Furina:BAAANQADCgMIAwAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
Ga='Galaxsea:BAAANQAECgUIEQAAAA==.Gale:BAAANQADCgYIBwABNQAECgUIDQAHAAAAAA==.Gamefreak:BAAANQAECgQIBAAAAA==.',
Ge='Gerthquake:BAAANQAECgEIAQAAAA==.',
Gh='Ghostfreak:BAAANQAECgcIEwAAAA==.',
Go='Gobø:BAAANQADCgEIAQAAAA==.Gooby:BAAANQAECgUICQAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAAANQAECgQJBQAAAA==.Haranjer:BAAANQAECgcIDgAAAA==.',
He='Hefferhumper:BAAANQAECgUJCwAAAA==.',
Ho='Homlock:BAAANQADCgYICwABNQAFFAUICgAOAIAWAA==.Homslam:BAAANQAECgYICwABNQAFFAUICgAOAIAWAA==.Homsorc:BAACNQAFFIEKAAIOAAUKgBaFCQDCAQAOAAUKgBaFCQDCAQA1AAQKgR4AAg4ACQrdJJEMAJADAA4ACQrdJJEMAJADAAAA.Homstab:BAABNQAECoEZAAMRAAkKrR2DDQBtAgARAAcK8h2DDQBtAgASAAIKvBzHVwBTAAAAAA==.Homtotem:BAAANQADCggICAABNQAFFAUICgAOAIAWAA==.Homwiz:BAAANQADCgMIAwAAAA==.Hope:BAAANQAECgcJEwAAAA==.',
Ic='Icons:BAAANQAECggICAAAAA==.Icyshaft:BAAANQADCgMIAwABNQAFFAMIBgATAAsZAA==.',
Il='Illiandray:BAAANQAECgYIDwAAAA==.',
In='Insomniac:BAAANQAECgYJDgAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgYIEgAAAA==.Jagernaut:BAAANQAECgUJCwAAAA==.Jake:BAAANQADCgIIAgAAAA==.Jangaballs:BAAANQAECgUJBwAAAA==.Jawndie:BAAANQAECgYJDQAAAA==.',
Jo='Joker:BAAANQAECgIIAgAAAA==.',
Jy='Jynn:BAAANQAECgEJAQABNQAECggJFwAUAPwdAA==.',
Ka='Kaalgormi:BAAANQABCgcICQAAAA==.Kammo:BAABNQAECoEZAAIVAAgKUB8fDgDKAgAVAAgKUB8fDgDKAgAAAA==.Kassa:BAAANQADCggIEAAAAA==.',
Ke='Keeah:BAAANQAECgQIBgAAAA==.Kestra:BAAANQAECgcJEwAAAA==.',
Ki='Kittysprigg:BAAANQAECgYICwAAAA==.',
Kl='Klingnor:BAAANQADCgcJBwAAAA==.',
Kr='Kravensteak:BAACNQAFFIEGAAITAAMKCxm9CgD/AAATAAMKCxm9CgD/AAA1AAQKgRwAAhMACAoMIHMQAKUCABMACAoMIHMQAKUCAAAA.',
Kw='Kwickin:BAAANQAECgEIAQABNQAECgIIBAAHAAAAAA==.',
Ky='Kyreen:BAAANQAECgQIBgAAAA==.',
['Kä']='Kärl:BAAANQADCgYIBwABNQAECgUIEQAHAAAAAA==.',
Le='Leonelda:BAAANQADCgUIBQAAAA==.Leylines:BAABNQAECoEbAAIOAAgKGxaDdQAzAgAOAAgKGxaDdQAzAgAAAA==.',
Lu='Lukafox:BAAANQAECgQJBwAAAA==.Lunastarvale:BAAANQAECgUICQAAAA==.Lunereclipse:BAAANQAECgQJBAAAAA==.',
Ma='Macha:BAAANQAECgcJEwAAAA==.Madith:BAAANQAECgQIBwAAAA==.Maintarget:BAAANQAECgYIDgAAAA==.Malefisico:BAAANQAECgQICAAAAA==.Mardríft:BAABNQAECoEZAAIWAAkK3hlvGQCsAgAWAAkK3hlvGQCsAgAAAA==.Marero:BAAANQADCgYICQAAAA==.Martyr:BAAANQAECgcJDAAAAA==.Mazga:BAAANQAECgYIDgAAAA==.',
Mc='Mcflury:BAAANQADCgUIBQAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.Mezoti:BAAANQADCggICgAAAA==.',
Mi='Mick:BAAANQAECgYICQAAAA==.Miraclehwip:BAAANQADCggICQAAAA==.',
Mo='Moaxzy:BAAANQAECgEIAQAAAA==.Moji:BAABNQAECoEaAAILAAgKnQ4ZEwDFAQALAAgKnQ4ZEwDFAQAAAA==.Monstermayi:BAABNQAECoEYAAMXAAcK0BBVCQC7AQAXAAcK0BBVCQC7AQAMAAIK8gtj4AByAAAAAA==.Mooknight:BAAANQAECgYJDgAAAA==.Morgoth:BAAANQAECgQICgAAAA==.Morteesha:BAAANQABCgQIBAABNQAECgYJDQAHAAAAAA==.',
Mu='Muggy:BAAANQAECgYIDgAAAA==.',
My='Myrothar:BAAANQADCgQIBAAAAA==.Mytastical:BAAANQAECgIIBQAAAA==.',
['Må']='Måzikeen:BAAANQADCgMIAwAAAA==.',
Na='Najwah:BAAANQAECgYICwAAAA==.Namalis:BAABNQAECoEZAAMCAAkKxh+LHgCyAgACAAgKpB+LHgCyAgAQAAMKyRZWMgDWAAAAAA==.Nanielito:BAAANQAECgcIDgAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQIBwAAAA==.Nerra:BAAANQADCggIDQAAAA==.',
Ni='Nineball:BAAANQADCgIIAgABNQAECgcIEQAHAAAAAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAAANQAECgUICAAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosali:BAAANQAECgUICQABNQAECggIGQAYAKQVAA==.Nosliw:BAAANQADCgYICwAAAA==.Noxilis:BAAANQAECgQIBAAAAA==.',
Nu='Nuggetz:BAAANQADCggICQAAAA==.',
['Nï']='Nïghtman:BAAANQAECgUIBgAAAA==.',
Om='Omegá:BAAANQAECgMIBAABNQAECgcIFAADAJEMAA==.',
Op='Optìmusprìme:BAAANQAECgYJCwAAAA==.',
Pa='Pandalock:BAAANQAECgYJDQAAAA==.Pandemic:BAAANQAECgQIBQAAAA==.Papa:BAABNQAECoEYAAQZAAcK2BJTDQABAQAQAAQKHRLhKAAMAQAZAAQKvw9TDQABAQACAAMK1g4rtwC1AAAAAA==.Pawfu:BAAANQAECgYIDgAAAA==.',
Pe='Penywize:BAAANQAECgUIDAAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgEIBAAAAA==.',
Po='Pockets:BAAANQAECgcIEQAAAA==.',
Pr='Prenus:BAAANQAECgUJBwAAAA==.',
Ps='Psychic:BAABNQAECoEXAAIUAAgK/B0ZAgDEAgAUAAgK/B0ZAgDEAgAAAA==.',
Pu='Purge:BAAANQAECgIIBAAAAA==.',
Qr='Qrazi:BAABNQAECoEaAAIFAAgKjBKkOAAbAgAFAAgKjBKkOAAbAgAAAA==.',
Qu='Quick:BAAANQAECgIIBAAAAA==.',
Ra='Ratha:BAABNQAECoEbAAIaAAgKYx4dCQCpAgAaAAgKYx4dCQCpAgAAAA==.Ravincible:BAAANQADCggIFgAAAA==.',
Ri='Ribbz:BAAANQADCgYICwAAAA==.',
Ro='Roguechin:BAACNQAFFIEPAAMRAAYKMR5OAgDnAQARAAUK5xxOAgDnAQASAAIKeCH3BQDHAAA1AAQKgR8AAxEACQrYJTIEADwDABEACAr6JTIEADwDABIABQpMIREiAMkBAAAA.Rokkgar:BAAANQAECgUJDAAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAAANQAECggIDgAAAA==.',
Sa='Sageara:BAAANQAECgQIBAAAAA==.Samirath:BAAANQAECgUICAAAAA==.',
Sc='Scared:BAACNQAFFIEGAAIYAAUKqAUVCAB9AQAYAAUKqAUVCAB9AQA1AAQKgS4AAhgACQrTGlgXAMgCABgACQrTGlgXAMgCAAAA.',
Se='Secarious:BAAANQAECgIIAgAAAA==.Sehnsucht:BAABNQAECoEXAAMbAAcKNhVfGgDTAQAbAAcKNhVfGgDTAQAcAAIKHQtpKwBVAAAAAA==.',
Sh='Shakti:BAAANQAECgUIBQAAAA==.Shieldcow:BAAANQAECgEIAgAAAA==.Shmadu:BAAANQAECgcICQAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.',
So='Soola:BAAANQADCggICAABNQAECggIGwAaAGMeAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stonedpriest:BAAANQADCggIFwAAAA==.',
Su='Surrëal:BAABNQAECoEVAAIBAAgKHQM8QwDmAAABAAgKHQM8QwDmAAAAAA==.',
Sy='Sybela:BAAANQABCgYIDAABNQAECgkJGgAYAEgaAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAAANQAECgYJDgAAAA==.Tanidge:BAAANQADCgQIBAABNQAECggIGAAFAEQcAA==.Tanidgemage:BAAANQADCgQIBAABNQAECggIGAAFAEQcAA==.Tanidgetotem:BAABNQAECoEYAAIFAAgKRBxPIwCYAgAFAAgKRBxPIwCYAgAAAA==.',
Te='Teias:BAABNQAECoEZAAMYAAgKpBVIPgDvAQAYAAgKpBVIPgDvAQAdAAEKRhwxSwBSAAAAAA==.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
Ti='Tirael:BAAANQAECgEJAQABNQAECggIGQAYAKQVAA==.',
To='Torvald:BAAANQADCggICAABNQADCgYICwAHAAAAAA==.',
Tr='Tricko:BAAANQAECgYIDgAAAA==.Trickshots:BAAANQADCgMIAwABNQAECgcIEQAHAAAAAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollbi:BAAANQADCgQIAgAAAA==.Trollfacion:BAAANQADCgYIBgAAAA==.Trollskingx:BAAANQAECgYJEAAAAA==.Trollzy:BAAANQAECgYJDgAAAA==.Trunkmonkey:BAAANQAECgYIDgAAAA==.Trunky:BAAANQADCgMJBgAAAA==.',
Ts='Tsaagan:BAABNQAECoEaAAICAAgKJCAsHQC5AgACAAgKJCAsHQC5AgAAAA==.',
Um='Umbrosa:BAAANQADCgcIBwABNQAECgcJEwAHAAAAAA==.',
Va='Valica:BAAANQADCgIIAQAAAA==.Valiithria:BAAANQADCgYIEgAAAA==.Valkyruid:BAAANQAECgcJDwAAAA==.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQAECgEIAgAAAA==.',
Vu='Vulgan:BAAANQADCgcICAAAAA==.',
Wa='Waywatcher:BAAANQAECgQIBAAAAA==.',
Wh='Whiilow:BAAANQAECgQICgAAAA==.',
Wu='Wullgan:BAAANQAECgYIDwAAAA==.',
Xe='Xencure:BAAANQAECgYJCgAAAA==.Xerk:BAAANQADCgMIAwABNQAECgUIBgAHAAAAAA==.',
Xy='Xyrna:BAAANQAECgYIDQABNQAECggIGwAaAGMeAA==.',
Ya='Yareli:BAAANQAECgYIDgAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAAANQAECgQJCgAAAA==.',
Ze='Zeleck:BAAANQAECgQIBAAAAA==.Zeno:BAACNQAFFIEMAAIIAAUK6iG+AQD7AQAIAAUK6iG+AQD7AQA1AAQKgSIAAggACQqwJZAFALUDAAgACQqwJZAFALUDAAAA.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAAANQAECgUJDAABNQAECgUJDAAHAAAAAA==.',
Zi='Zinbar:BAAANQAECgUJCQAAAA==.',
Zo='Zoroark:BAAANQADCggIEAABNQAECggIGwAOABsWAA==.',
Zu='Zuggzugg:BAAANQADCgYIBgAAAA==.Zune:BAAANQAECgUIDQAAAA==.',
['Çl']='Çloud:BAAANQAECgIIAwAAAA==.',
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
