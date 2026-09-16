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

local lookup = {'Warlock-Demonology','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Retribution','Warrior-Arms','Mage-Arcane','Paladin-Holy','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Shaman-Elemental',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaylasecura:BAAANQAECgcIEQAAAA==.',
Ab='Abelladanger:BAAANQADCgQIBAAAAA==.Abracadavar:BAAANQADCgEIAQABNQAFFAYIDQABAIYeAA==.Absinth:BAAANQAECgcIDwAAAA==.',
Ai='Airfriend:BAAANQAECgcIEQAAAA==.',
Al='Alder:BAAANQAECgQIBAAAAA==.Alphard:BAAANQAECgQICAAAAA==.',
An='Anelowyn:BAAANQAECgQICAAAAA==.Angrychicken:BAAANQADCgMIAwAAAA==.',
Ap='Apocal:BAABNQAECoEbAAICAAkJ1iGqAACEAwACAAkJ1iGqAACEAwAAAA==.',
Ar='Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAAANQADCggIEQAAAA==.Asmozaps:BAAANQAECgQIBAAAAA==.',
Az='Aziel:BAAANQAECgUIBQAAAA==.Azmodeaus:BAAANQADCgcIBwAAAA==.',
Ba='Baraden:BAAANQAECgMIBAAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQADCgYICgAAAA==.Billiards:BAAANQADCggICAABNQAECgYIDAADAAAAAA==.Birgetta:BAAANQADCggICAABNQAECgUIDQADAAAAAA==.',
Bl='Blorne:BAAANQAECgQICAAAAA==.',
Bo='Bobodaklown:BAABNQAECoEVAAIEAAcJHxqiOAAcAgAEAAcJHxqiOAAcAgAAAA==.Boombawks:BAAANQADCgUICQAAAA==.Boomnbrew:BAAANQAECgcIEQAAAA==.Bownir:BAAANQAECgQIBAAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAAANQAECgYIEAAAAA==.',
Bu='Bubonic:BAAANQAECgUIBQAAAA==.Buenasalud:BAAANQAECgQICAAAAA==.',
Ca='Caylea:BAABNQAECoEbAAIFAAkJvRz3GgD1AgAFAAkJvRz3GgD1AgAAAA==.',
Ch='Chalis:BAAANQAECgQIBwAAAA==.',
Cl='Clamsquirter:BAAANQAECgcIDQAAAA==.',
Co='Coldhwip:BAAANQAECgUIDAAAAA==.',
Cr='Crash:BAABNQAECoEcAAIFAAgJjBvvLQCKAgAFAAgJjBvvLQCKAgAAAA==.Crtaker:BAAANQAECgcICAAAAA==.Crysis:BAAANQAECgUIDAAAAA==.',
Cu='Cuahtemoc:BAAANQADCgQIBwAAAA==.',
Da='Dabss:BAAANQAECgEIAQAAAA==.Daelin:BAAANQAECgQICAAAAA==.Dagda:BAAANQADCgYIDAAAAA==.Danye:BAAANQAECgEIAQAAAA==.Darkscout:BAAANQADCgUIDQAAAA==.',
De='Decease:BAAANQAECgQIBAABNQAECgcIDwADAAAAAA==.Delium:BAABNQAECoEdAAIGAAkJRSHPFABNAwAGAAkJRSHPFABNAwAAAA==.Demonmommy:BAAANQADCgYIBgAAAA==.Deäthrose:BAAANQAECgcIEQAAAA==.',
Di='Die:BAAANQAECgIIAwAAAA==.Diegoo:BAAANQADCgUIBQAAAA==.Disc:BAAANQADCgQIBgAAAA==.',
Do='Doadin:BAABNQAECoEVAAIHAAcJIxfmLgAKAgAHAAcJIxfmLgAKAgAAAA==.Doominatrix:BAAANQAECgcIEAAAAA==.Dotem:BAAANQADCgYICgAAAA==.',
Dr='Dreadraven:BAAANQADCgYIDAAAAA==.Drip:BAAANQAECgIIAgAAAA==.Druidhams:BAAANQAECgcIDQAAAA==.',
Du='Dunktars:BAAANQAECgcIEQAAAA==.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBgAAAA==.',
Ei='Eightball:BAAANQADCggIFgABNQAECgYIDAADAAAAAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBgADAAAAAA==.Elisha:BAABNQAECoEhAAIEAAcJ9Q5uVwCcAQAEAAcJ9Q5uVwCcAQAAAA==.',
Er='Erebostro:BAAANQAECgQICAAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgMIBAAAAA==.Fauxphoe:BAAANQADCgMIAwAAAA==.Fauxtotem:BAAANQAECgYIEAAAAA==.',
Fe='Fender:BAAANQAECgEIAQAAAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAAANQAECgcIEQAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAECgUIDQADAAAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
Ga='Galaxsea:BAAANQAECgQIDAAAAA==.Gamefreak:BAAANQAECgQIBAAAAA==.',
Ge='Gerthquake:BAAANQAECgEIAQAAAA==.',
Gh='Ghostfreak:BAAANQAECgcIEwAAAA==.',
Go='Gobø:BAAANQADCgEIAQAAAA==.Gooby:BAAANQAECgQIBAAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAAANQAECgEIAQAAAA==.Haranjer:BAAANQAECgcIDgAAAA==.',
He='Hefferhumper:BAAANQAECgQIBgAAAA==.',
Ho='Homlock:BAAANQADCgYICwABNQAFFAMIBQAGAAEcAA==.Homslam:BAAANQAECgQICAABNQAFFAMIBQAGAAEcAA==.Homsorc:BAACNQAFFIEFAAIGAAMJARyzCwAmAQAGAAMJARyzCwAmAQA1AAQKgRoAAgYACQnzI84LAIIDAAYACQnzI84LAIIDAAAA.Homstab:BAAANQAECgcIDAAAAA==.Homtotem:BAAANQADCggICAABNQAFFAMIBQAGAAEcAA==.Hope:BAAANQAECgYIDAAAAA==.',
Ic='Icons:BAAANQAECggICAAAAA==.Icyshaft:BAAANQADCgMIAwABNQAECggIGQAIAAweAA==.',
Il='Illiandray:BAAANQAECgUICQAAAA==.',
In='Insomniac:BAAANQAECgQICAAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgYIEgAAAA==.Jagernaut:BAAANQAECgUIBgAAAA==.Jangaballs:BAAANQAECgIIAgAAAA==.Jawndie:BAAANQAECgQIBwAAAA==.',
Jo='Joker:BAAANQAECgIIAgAAAA==.',
Ka='Kaalgormi:BAAANQABCgcICQAAAA==.Kammo:BAAANQAECgcIDwAAAA==.Kassa:BAAANQADCggICAAAAA==.',
Ke='Keeah:BAAANQAECgIIAgAAAA==.Kestra:BAAANQAECgUIDAAAAA==.',
Ki='Kittysprigg:BAAANQAECgUIBgAAAA==.',
Kr='Kravensteak:BAABNQAECoEZAAIIAAgJDB4NEACGAgAIAAgJDB4NEACGAgAAAA==.',
Kw='Kwickin:BAAANQADCggIDAABNQAECgEIAQADAAAAAA==.',
Ky='Kyreen:BAAANQAECgIIAgAAAA==.',
Le='Leonelda:BAAANQADCgUIBQAAAA==.Leylines:BAAANQAECgYIEAAAAA==.',
Lu='Lukafox:BAAANQAECgQIBAAAAA==.Lunastarvale:BAAANQAECgQIBAAAAA==.Lunereclipse:BAAANQAECgQIBAAAAA==.',
Ma='Macha:BAAANQAECgUIDAAAAA==.Madith:BAAANQAECgQIBwAAAA==.Maintarget:BAAANQAECgYICQAAAA==.Malefisico:BAAANQAECgQICAAAAA==.Mardríft:BAAANQAECgcIEAAAAA==.Marero:BAAANQADCgYICQAAAA==.Martyr:BAAANQAECgUIBQAAAA==.Mazga:BAAANQAECgQICAAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.Mezoti:BAAANQADCgcIBwAAAA==.',
Mi='Mick:BAAANQAECgYICQAAAA==.Miraclehwip:BAAANQADCgcIBwAAAA==.',
Mo='Moaxzy:BAAANQAECgEIAQAAAA==.Moji:BAAANQAECgYIEAAAAA==.Monstermayi:BAAANQAECgcIEQAAAA==.Mooknight:BAAANQAECgQICAAAAA==.Morgoth:BAAANQAECgQIBQAAAA==.Morteesha:BAAANQABCgQIBAABNQAECgQIBwADAAAAAA==.',
Mu='Muggy:BAAANQAECgUICAAAAA==.',
My='Myrothar:BAAANQADCgQIBAAAAA==.Mytastical:BAAANQAECgIIAwAAAA==.',
['Må']='Måzikeen:BAAANQADCgMIAwAAAA==.',
Na='Najwah:BAAANQAECgUIBwAAAA==.Namalis:BAAANQAECgcIDwAAAA==.Nanielito:BAAANQAECgQIBwAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQIBwAAAA==.Nerra:BAAANQADCggIDQAAAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAAANQAECgUICAAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosali:BAAANQAECgQIBAABNQAECgYIDgADAAAAAA==.Nosliw:BAAANQADCgYICwAAAA==.',
Nu='Nuggetz:BAAANQADCggICQAAAA==.',
['Nï']='Nïghtman:BAAANQAECgUIBgAAAA==.',
Om='Omegá:BAAANQAECgIIAgABNQAECgcIDwADAAAAAA==.',
Op='Optìmusprìme:BAAANQAECgQIBQAAAA==.',
Pa='Pandalock:BAAANQAECgQIBwAAAA==.Pandemic:BAAANQAECgEIAQAAAA==.Papa:BAAANQAECgYIEgAAAA==.Pawfu:BAAANQAECgUICAAAAA==.',
Pe='Penywize:BAAANQAECgQICAAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgEIAwAAAA==.',
Po='Pockets:BAAANQAECgYIDAAAAA==.',
Pr='Prenus:BAAANQAECgUIBQAAAA==.',
Ps='Psychic:BAAANQAECgYIDQAAAA==.',
Pu='Purge:BAAANQAECgEIAQAAAA==.',
Qr='Qrazi:BAAANQAECgYIDwAAAA==.',
Qu='Quick:BAAANQAECgEIAQAAAA==.',
Ra='Ratha:BAAANQAECgYIEAAAAA==.Ravincible:BAAANQADCggIFAAAAA==.',
Ri='Ribbz:BAAANQADCgYICwAAAA==.',
Ro='Roguechin:BAACNQAFFIEKAAMJAAUJDR+TAgCNAQAJAAQJqB2TAgCNAQAKAAIJeCHxAgDQAAA1AAQKgRwAAwkACQnYJQ8DAFMDAAkACAn6JQ8DAFMDAAoABQlMIXoWANwBAAAA.Rokkgar:BAAANQAECgUIBwAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAAANQAECggICwAAAA==.',
Sa='Sageara:BAAANQAECgQIBAAAAA==.Samirath:BAAANQAECgIIAwAAAA==.',
Sc='Scared:BAABNQAECoElAAILAAkJ6xlCEQC+AgALAAkJ6xlCEQC+AgAAAA==.Scottamus:BAABNQAECoEXAAIGAAkJbB7sKgDlAgAGAAkJbB7sKgDlAgAAAA==.',
Se='Secarious:BAAANQAECgIIAgAAAA==.Sehnsucht:BAAANQAECgUIDwAAAA==.',
Sh='Shakti:BAAANQAECgUIBQAAAA==.Shieldcow:BAAANQAECgEIAQAAAA==.Shmadu:BAAANQAECgcICQAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.',
So='Soola:BAAANQADCggICAABNQAECgYIEAADAAAAAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stonedpriest:BAAANQADCggIDwAAAA==.',
Su='Surrëal:BAAANQAECgUIDQAAAA==.',
Sy='Sybela:BAAANQABCgYIDAABNQAECgYIDwADAAAAAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAAANQAECgQICAAAAA==.Tanidge:BAAANQADCgQIBAABNQAECggIFgAMAAAcAA==.Tanidgemage:BAAANQADCgQIBAABNQAECggIFgAMAAAcAA==.Tanidgetotem:BAABNQAECoEWAAIMAAgJAByxGQCnAgAMAAgJAByxGQCnAgAAAA==.',
Te='Teias:BAAANQAECgYIDgAAAA==.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
Ti='Tirael:BAAANQADCggICAABNQAECgYIDgADAAAAAA==.',
To='Torvald:BAAANQADCggICAABNQADCgYICwADAAAAAA==.',
Tr='Tricko:BAAANQAECgQICAAAAA==.Trickshots:BAAANQADCgMIAwABNQAECgYIDAADAAAAAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollbi:BAAANQABCgEIAQAAAA==.Trollfacion:BAAANQADCgYIBgAAAA==.Trollskingx:BAAANQAECgYICgAAAA==.Trollzy:BAAANQAECgQICAAAAA==.Trunkmonkey:BAAANQAECgUICAAAAA==.Trunky:BAAANQADCgMIAwAAAA==.',
Ts='Tsaagan:BAAANQAECgcIEQAAAA==.',
Um='Umbrosa:BAAANQADCgQIBAABNQAECgUIDAADAAAAAA==.',
Va='Valica:BAAANQADCgIIAQAAAA==.Valiithria:BAAANQADCgYIEgAAAA==.Valkyruid:BAAANQAECgcIDgAAAA==.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQAECgEIAQAAAA==.',
Vu='Vulgan:BAAANQADCgcICAAAAA==.',
Wa='Waywatcher:BAAANQAECgQIBAAAAA==.',
Wh='Whiilow:BAAANQAECgQICgAAAA==.',
Wu='Wullgan:BAAANQAECgUICQAAAA==.',
Xe='Xencure:BAAANQAECgYICQAAAA==.Xerk:BAAANQADCgMIAwABNQAECgUIBgADAAAAAA==.',
Xy='Xyrna:BAAANQAECgUIBwABNQAECgYIEAADAAAAAA==.',
Ya='Yareli:BAAANQAECgUICAAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAAANQAECgQIBgAAAA==.',
Ze='Zeleck:BAAANQABCgQIBAAAAA==.Zeno:BAACNQAFFIEHAAIEAAQJkhXNAgBiAQAEAAQJkhXNAgBiAQA1AAQKgR8AAgQACQlfJXMDAMEDAAQACQlfJXMDAMEDAAAA.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAAANQAECgUIBwABNQAECgUIBwADAAAAAA==.',
Zi='Zinbar:BAAANQAECgUIBQAAAA==.',
Zo='Zoroark:BAAANQADCggIEAABNQAECgYIEAADAAAAAA==.',
Zu='Zuggzugg:BAAANQADCgYIBgAAAA==.Zune:BAAANQAECgQICAAAAA==.',
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
