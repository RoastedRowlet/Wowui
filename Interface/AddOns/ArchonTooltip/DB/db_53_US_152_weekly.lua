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

local lookup = {'Warlock-Destruction','Unknown-Unknown','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaylasecura:BAAANQAECgYICgAAAA==.',
Ab='Abracadavar:BAAANQADCgEIAQABNQAFFAUICAABAPYbAA==.Absinth:BAAANQAECgUICgAAAA==.',
Ai='Airfriend:BAAANQAECgYICgAAAA==.',
Al='Alder:BAAANQADCgcICAAAAA==.Alphard:BAAANQAECgMIBAAAAA==.',
An='Anelowyn:BAAANQAECgMIBAAAAA==.',
Ap='Apocal:BAAANQAECgcIEgAAAA==.',
Ar='Arthritis:BAAANQADCgUIBQAAAA==.',
As='Asmodyus:BAAANQADCgUICQAAAA==.Asmozaps:BAAANQADCggIDgAAAA==.',
Az='Azmodeaus:BAAANQADCgcIBwAAAA==.',
Be='Beefblood:BAAANQAECgMIBAAAAA==.',
Bh='Bhxrafiq:BAAANQADCgYIBgAAAA==.',
Bi='Bigtimmehss:BAAANQADCgYICgAAAA==.Billiards:BAAANQADCggICAABNQAECgYIBgACAAAAAA==.Birgetta:BAAANQADCggICAABNQAECgQICAACAAAAAA==.',
Bl='Blorne:BAAANQAECgQIBQAAAA==.',
Bo='Bobodaklown:BAAANQAECgcIDgAAAA==.Boombawks:BAAANQADCgUICQAAAA==.Boomnbrew:BAAANQAECgUICgAAAA==.Bownir:BAAANQADCgcIDgAAAA==.',
Br='Braelsong:BAAANQAECgEIAQAAAA==.Brewman:BAAANQAECgYICgAAAA==.',
Bu='Buenasalud:BAAANQAECgMIBAAAAA==.',
Ca='Caylea:BAAANQAECggIEAAAAA==.',
Ch='Chalis:BAAANQAECgMIAwAAAA==.',
Cl='Clamsquirter:BAAANQAECgUIBgAAAA==.',
Co='Coldhwip:BAAANQAECgQIBwAAAA==.',
Cr='Crash:BAAANQAECgcIEQAAAA==.Crtaker:BAAANQAECgUIBQAAAA==.Crysis:BAAANQAECgQIBwAAAA==.',
Cu='Cuahtemoc:BAAANQADCgQIBwAAAA==.',
Da='Dabss:BAAANQADCgcIBwAAAA==.Daelin:BAAANQAECgMIBAAAAA==.Dagda:BAAANQADCgYIBgAAAA==.Danye:BAAANQADCgcIBwAAAA==.Darkscout:BAAANQADCgQICAAAAA==.',
De='Delium:BAABNQAECoEUAAIDAAgJoiEzHgDiAgADAAgJoiEzHgDiAgAAAA==.Demonmommy:BAAANQADCgYIBgAAAA==.Deäthrose:BAAANQAECgUICgAAAA==.',
Di='Die:BAAANQAECgEIAQAAAA==.Disc:BAAANQADCgQIBgAAAA==.',
Do='Doadin:BAAANQAECgcIDgAAAA==.Doominatrix:BAAANQAECgUICQAAAA==.Dotem:BAAANQADCgYICgAAAA==.',
Dr='Dreadraven:BAAANQADCgYIDAAAAA==.Druidhams:BAAANQAECgUIBgAAAA==.',
Du='Dunktars:BAAANQAECgUICgAAAA==.Durpy:BAAANQADCgIIAwAAAA==.',
Eg='Egri:BAAANQAECgQIBQAAAA==.',
Ei='Eightball:BAAANQADCggIFgABNQAECgYIBgACAAAAAA==.',
El='Electro:BAAANQADCgYIBgABNQAECgQIBQACAAAAAA==.Elisha:BAAANQAECgYIEAAAAA==.',
Er='Erebostro:BAAANQAECgMIBAAAAA==.',
Fa='Facheritor:BAAANQADCgUIBAAAAA==.Fastlane:BAAANQAECgMIBAAAAA==.Fauxtotem:BAAANQAECgYICgAAAA==.',
Fe='Fender:BAAANQAECgEIAQAAAA==.Ferren:BAAANQABCgQIBAAAAA==.',
Fi='Fingies:BAAANQAECgYICgAAAA==.',
Fl='Flexyheals:BAAANQABCgQIBQAAAA==.',
Fr='Freakbeast:BAAANQAECgEIAQABNQAECgUICQACAAAAAA==.',
['Fë']='Fënn:BAAANQAECgQIBQAAAA==.',
Ga='Galaxsea:BAAANQAECgQICAAAAA==.Gamefreak:BAAANQAECgQIBAAAAA==.',
Ge='Gerthquake:BAAANQAECgEIAQAAAA==.',
Gh='Ghostfreak:BAAANQAECgcIDQAAAA==.',
Go='Gobø:BAAANQADCgEIAQAAAA==.Gooby:BAAANQADCgEIAQAAAA==.',
Gr='Grindlemorph:BAAANQADCgYICAAAAA==.',
Ha='Hacks:BAAANQADCggIEQAAAA==.Haranjer:BAAANQAECgcIDgAAAA==.',
He='Hefferhumper:BAAANQAECgIIAgAAAA==.',
Ho='Homlock:BAAANQADCgYIBgABNQAECgkJFwADANEiAA==.Homslam:BAAANQAECgQIBAABNQAECgkJFwADANEiAA==.Homsorc:BAABNQAECoEXAAIDAAkJ0SJcBwCIAwADAAkJ0SJcBwCIAwAAAA==.Homstab:BAAANQAECgYICwAAAA==.Homtotem:BAAANQADCggICAABNQAECgkJFwADANEiAA==.Hope:BAAANQAECgQIBgAAAA==.',
Ic='Icons:BAAANQAECggICAAAAA==.',
Il='Illiandray:BAAANQAECgQIBAAAAA==.',
In='Insomniac:BAAANQAECgMIBAAAAA==.',
Is='Isklar:BAAANQADCgcIBwAAAA==.',
Ja='Jaegernaut:BAAANQADCgQIDAAAAA==.Jagernaut:BAAANQAECgEIAQAAAA==.Jangaballs:BAAANQADCgUIBQAAAA==.Jawndie:BAAANQAECgIIAwAAAA==.',
Jo='Joker:BAAANQADCggIFgAAAA==.',
Ka='Kaalgormi:BAAANQABCgIIAgAAAA==.Kammo:BAAANQAECgQICAAAAA==.',
Ke='Keeah:BAAANQADCgYIBwAAAA==.Kestra:BAAANQAECgQIBwAAAA==.',
Ki='Kittysprigg:BAAANQAECgEIAQAAAA==.',
Kr='Kravensteak:BAABNQAECoEUAAIEAAgJuxy1CwCgAgAEAAgJuxy1CwCgAgAAAA==.',
Kw='Kwickin:BAAANQADCggIDAABNQAECgUIBQACAAAAAA==.',
Ky='Kyreen:BAAANQADCgcIDgAAAA==.',
Le='Leylines:BAAANQAECgYICgAAAA==.',
Lu='Lukafox:BAAANQADCggICAAAAA==.Lunastarvale:BAAANQAECgQIBAAAAA==.Lunereclipse:BAAANQADCgYIBgAAAA==.',
Ma='Macha:BAAANQAECgQIBwAAAA==.Madith:BAAANQAECgIIAwAAAA==.Maintarget:BAAANQAECgMIAwAAAA==.Malefisico:BAAANQAECgMIBAAAAA==.Mardríft:BAAANQAECgcIDQAAAA==.Marero:BAAANQADCgUIBgAAAA==.Mazga:BAAANQAECgMIBAAAAA==.',
Me='Melee:BAAANQADCgYIDAAAAA==.',
Mi='Mick:BAAANQAECgIIAwAAAA==.',
Mo='Moji:BAAANQAECgYICgAAAA==.Monstermayi:BAAANQAECgUICgAAAA==.Mooknight:BAAANQAECgMIBAAAAA==.Morgoth:BAAANQAECgQIBAAAAA==.Morteesha:BAAANQABCgQIBAABNQAECgIIAwACAAAAAA==.',
Mu='Muggy:BAAANQAECgIIAwAAAA==.',
My='Myrothar:BAAANQADCgQIBAAAAA==.Mytastical:BAAANQAECgIIAgAAAA==.',
Na='Najwah:BAAANQAECgEIAQAAAA==.Namalis:BAAANQAECgQICAAAAA==.Nanielito:BAAANQAECgQIBwAAAA==.',
Ne='Necrotik:BAAANQADCgIIAgAAAA==.Neffer:BAAANQAECgQIBwAAAA==.Nerra:BAAANQADCgYIBgAAAA==.',
No='Nobunaka:BAAANQADCgYIBgAAAA==.Nonae:BAAANQAECgIIAwAAAA==.Norivari:BAAANQADCgYICwAAAA==.Nosliw:BAAANQADCgYICwAAAA==.',
['Nï']='Nïghtman:BAAANQAECgEIAQAAAA==.',
Om='Omegá:BAAANQADCgYIBgABNQAECgUICgACAAAAAA==.',
Op='Optìmusprìme:BAAANQAECgEIAQAAAA==.',
Pa='Pandalock:BAAANQAECgIIAwAAAA==.Pandemic:BAAANQADCgYIBgAAAA==.Papa:BAAANQAECgUIDAAAAA==.Pawfu:BAAANQAECgIIAwAAAA==.',
Pe='Penywize:BAAANQAECgQIBAAAAA==.',
Pi='Pilo:BAAANQADCgUICAAAAA==.',
Pl='Planeteer:BAAANQAECgEIAgAAAA==.',
Po='Pockets:BAAANQAECgYIBgAAAA==.',
Ps='Psychic:BAAANQAECgQIBwAAAA==.',
Qr='Qrazi:BAAANQAECgUICQAAAA==.',
Ra='Ratha:BAAANQAECgYICgAAAA==.Ravincible:BAAANQADCggIDgAAAA==.',
Ri='Ribbz:BAAANQADCgYIBgAAAA==.',
Ro='Roguechin:BAACNQAFFIEGAAMFAAUJoh1BAQCeAQAFAAQJqB1BAQCeAQAGAAEJih0LAwBmAAA1AAQKgRkAAwUACQk9JXwCAFADAAUACAlMJXwCAFADAAYABQlMITwMAOkBAAAA.Rokkgar:BAAANQAECgIIAgAAAA==.Rottontoe:BAAANQADCgEIAQAAAA==.',
Ru='Runa:BAAANQAECgUIBQAAAA==.',
Sa='Sageara:BAAANQADCgQIBAAAAA==.Samirath:BAAANQAECgEIAQAAAA==.',
Sc='Scared:BAAANQAECggIEAAAAA==.Scottamus:BAAANQAECggIEQAAAA==.',
Se='Sehnsucht:BAAANQAECgUIDQAAAA==.',
Sh='Shakti:BAAANQADCggIGAAAAA==.Shmadu:BAAANQAECgcICAAAAA==.Shockakhan:BAAANQADCgcIBwAAAA==.',
So='Soola:BAAANQADCggICAABNQAECgYICgACAAAAAA==.',
Sp='Spoof:BAAANQADCgYICwAAAA==.',
St='Stonedpriest:BAAANQADCggICAAAAA==.',
Su='Surrëal:BAAANQAECgQICAAAAA==.',
Sy='Sybela:BAAANQABCgYIDAABNQAECgYICgACAAAAAA==.',
Ta='Tahitian:BAAANQADCgIIAgAAAA==.Tahlreth:BAAANQAECgMIBAAAAA==.Tanidge:BAAANQADCgQIBAABNQAECgcIDgACAAAAAA==.Tanidgemage:BAAANQADCgQIBAABNQAECgcIDgACAAAAAA==.Tanidgetotem:BAAANQAECgcIDgAAAA==.',
Te='Teias:BAAANQAECgQICAAAAA==.Tersus:BAAANQADCgEIAQAAAA==.',
Th='Theleena:BAAANQABCgIIAgAAAA==.',
To='Torvald:BAAANQADCggICAABNQADCgYICwACAAAAAA==.',
Tr='Tricko:BAAANQAECgMIBAAAAA==.Trickshots:BAAANQADCgMIAwABNQAECgYIBgACAAAAAA==.Trogar:BAAANQADCgQIBwAAAA==.Trollskingx:BAAANQAECgQIBAAAAA==.Trollzy:BAAANQAECgMIBAAAAA==.Trunkmonkey:BAAANQAECgIIAwAAAA==.',
Ts='Tsaagan:BAAANQAECgUICgAAAA==.',
Va='Valiithria:BAAANQADCgUIDAAAAA==.Valkyruid:BAAANQAECgYIDAAAAA==.Varaxis:BAAANQABCgQIBgAAAA==.',
Ve='Veledreyssa:BAAANQADCgEIAQAAAA==.',
Vu='Vulgan:BAAANQADCgcICAAAAA==.',
Wh='Whiilow:BAAANQAECgQIBwAAAA==.',
Wu='Wullgan:BAAANQAECgQIBAAAAA==.',
Xe='Xencure:BAAANQAECgUICAAAAA==.',
Xy='Xyrna:BAAANQAECgQIBQABNQAECgYICgACAAAAAA==.',
Ya='Yareli:BAAANQAECgIIAwAAAA==.',
Yu='Yunara:BAAANQADCgUIBQAAAA==.',
Za='Zartman:BAAANQAECgIIAgAAAA==.',
Ze='Zeno:BAABNQAECoEXAAIHAAkJfSTxAgCpAwAHAAkJfSTxAgCpAwAAAA==.Zetetic:BAAANQADCggICAAAAA==.',
Zg='Zgystrdst:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.',
Zi='Zinbar:BAAANQAECgEIAQAAAA==.',
Zo='Zoroark:BAAANQADCggIEAABNQAECgYICgACAAAAAA==.',
Zu='Zuggzugg:BAAANQADCgUIBQAAAA==.Zune:BAAANQAECgQIBAAAAA==.',
['Çl']='Çloud:BAAANQAECgIIAgAAAA==.',
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
