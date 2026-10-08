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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Hunter-Survival','Unknown-Unknown','Hunter-BeastMastery','Paladin-Holy','Shaman-Elemental','DemonHunter-Devourer','Priest-Shadow','Evoker-Preservation','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Shaman-Enhancement','Monk-Windwalker','Hunter-Marksmanship','Evoker-Devastation','DemonHunter-Havoc','DeathKnight-Frost','Evoker-Augmentation','DemonHunter-Vengeance','Priest-Holy','DeathKnight-Unholy','Mage-Arcane','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms','Warrior-Protection','Rogue-Subtlety','Druid-Guardian','Mage-Frost','Warlock-Affliction',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Aceroth:BAABNQAECoEXAAMBAAkKtBOEXQBVAgABAAkKtBOEXQBVAgACAAEKnwY2bwAgAAAAAA==.Achärd:BAAANQAECggIEAAAAA==.',
Ae='Aelin:BAABNQAECoEjAAIDAAgKORZ+NAAbAgADAAgKORZ+NAAbAgAAAA==.Aerillidan:BAAANQAECgEIAQAAAA==.',
Ak='Akinna:BAAANQABCgYJBgAAAA==.',
Al='Alaysia:BAAANQADCgYIBgAAAA==.Alestair:BAAANQAECgcIEAAAAA==.Alythra:BAAANQADCgcIBwAAAA==.',
Am='Amorsith:BAABNQAECoEYAAIEAAcKrw52BwDQAQAEAAcKrw52BwDQAQAAAA==.Ampluslues:BAAANQADCgMIAgABNQADCggICAAFAAAAAA==.',
An='Angrä:BAAANQAECgQJBAAAAA==.',
Ar='Arakfalas:BAAANQADCggIDgAAAA==.Argentnox:BAAANQADCgUIBQABNQAECgYIGwAGAH0LAA==.Argoz:BAABNQAECoEZAAIHAAgKQgspbgCmAQAHAAgKQgspbgCmAQAAAA==.Arrethyn:BAAANQAECggIDAAAAA==.',
As='Asbell:BAAANQAECgcIDQAAAA==.Aspectz:BAAANQABCgMIAwAAAA==.',
At='Atsidi:BAABNQAECoEZAAIIAAgKVxcXRAA6AgAIAAgKVxcXRAA6AgAAAA==.',
Ax='Axecutioner:BAAANQAECgQIBgAAAA==.',
Az='Azaelara:BAAANQAECgYIEgAAAA==.Azaëlle:BAAANQADCgYIDAAAAA==.Azmerea:BAAANQADCggICAAAAA==.Azshaura:BAAANQADCgIIAgAAAA==.',
Ba='Badmojojojo:BAABNQAECoEbAAIGAAYKfQuEvABVAQAGAAYKfQuEvABVAQAAAA==.Bankhand:BAABNQAECoEdAAIJAAgKexBnJgDzAQAJAAgKexBnJgDzAQAAAA==.Bartab:BAAANQAECgUICQAAAA==.',
Be='Beazle:BAAANQADCgMIAwAAAA==.Beefytotems:BAAANQAECgYICAABNQAECggICQAFAAAAAA==.Benjamin:BAABNQAECoEZAAIKAAkKzRuHFQCRAgAKAAkKzRuHFQCRAgAAAA==.',
Bi='Bibistraz:BAABNQAECoEcAAILAAcKbhXYHgDEAQALAAcKbhXYHgDEAQAAAA==.',
Bl='Blenny:BAAANQAECgMIAwAAAA==.Blitzkrîeg:BAABNQAECoEdAAIHAAgKTRRkTAAYAgAHAAgKTRRkTAAYAgAAAA==.',
Bo='Boeboe:BAAANQAECgYIEAAAAA==.Boomloomly:BAABNQAECoEgAAMMAAgK/iEoFgD/AgAMAAgK/iEoFgD/AgANAAIKzAkzXABfAAAAAA==.Borgymorgy:BAAANQADCgEIAQAAAA==.',
Br='Brightblade:BAAANQADCgcIBwAAAA==.Bruzande:BAAANQAECgYJEAAAAA==.Brynjolf:BAAANQADCgYIBgAAAA==.',
Bu='Bumbaweatuna:BAAANQADCgEIAQAAAA==.Burncycle:BAAANQADCgYIBgAAAA==.Burntt:BAAANQABCgYIBgAAAA==.Buttjeans:BAABNQAECoEhAAMOAAkKdiB4HAD9AgAOAAgK4iB4HAD9AgAPAAIKYBJHTwCFAAAAAA==.',
Ca='Catastrophez:BAAANQADCgcIBwAAAA==.',
Ce='Celine:BAAANQAECgUIEQAAAA==.Ceo:BAAANQAECgEIAQAAAA==.',
Ch='Chev:BAAANQADCgUIBQAAAA==.Chickynuggy:BAAANQAECgQIDQAAAA==.Chillypickle:BAAANQAECgMIBAAAAA==.Christopher:BAABNQAECoEYAAIDAAkKqiH3DwAbAwADAAkKqiH3DwAbAwAAAA==.Chronicbuds:BAAANQAECgYIDQAAAA==.',
Cl='Cloudcaller:BAAANQADCgYIBgABNQAECggIIAAQAB4IAA==.Clyde:BAAANQADCgYJBgAAAA==.',
Co='Cobrakai:BAAANQAECgUICwAAAA==.Cochuata:BAAANQAECgcIEwAAAA==.',
Cr='Crabbypatty:BAAANQADCgcICwABNQABCgQIBAAFAAAAAA==.Cripstaet:BAAANQADCgYIBgAAAA==.Crow:BAAANQAECgEIAQAAAA==.Crusadinvee:BAAANQADCggICAAAAA==.',
Cu='Curse:BAAANQAECgQICAABNQAECgYIEAAFAAAAAA==.',
Da='Dairydefendr:BAABNQAECoEWAAIBAAcKrBmJcQAdAgABAAcKrBmJcQAdAgAAAA==.Damage:BAAANQADCggIDAAAAA==.Damyn:BAABNQAECoEiAAIRAAgK7xc/DQB/AgARAAgK7xc/DQB/AgAAAA==.Darogue:BAAANQAECgQIBAAAAA==.Darthsparrow:BAAANQAECgMIAwAAAA==.',
De='Deadbro:BAAANQADCgEIAQAAAA==.Deathaxe:BAAANQADCgUIBQABNQAECgYIEgAFAAAAAA==.Deathsgrace:BAAANQAECgYIEgAAAA==.Delia:BAAANQABCggIDgAAAA==.Demark:BAAANQAECgQIBAAAAA==.Demonicneon:BAAANQAECgYIEQAAAA==.Devana:BAABNQAECoEcAAIGAAcKsRwFUwBPAgAGAAcKsRwFUwBPAgAAAA==.',
Di='Diabolicque:BAAANQAECgEIAQAAAA==.Diddycated:BAEANQAECgUIBQABNQAECgkJKAASAJAWAA==.Dingus:BAABNQAECoEdAAQTAAgKFhsCHwA7AgATAAcK1RoCHwA7AgAEAAQKbRkdCgBDAQAGAAEK+Rh6JwFQAAAAAA==.',
Dk='Dk:BAAANQADCgYIDQABNQAECgYIEAAFAAAAAA==.',
Do='Doode:BAABNQAECoEgAAMLAAgKyQmMIgCUAQALAAgKyQmMIgCUAQAUAAEKmALrPQAjAAAAAA==.Doody:BAAANQADCgYIEAABNQAECggIIAALAMkJAA==.',
Dr='Dragonslayer:BAAANQADCgcIBwAAAA==.Dreastotems:BAAANQAECgEIAgAAAA==.Drennifer:BAAANQAECgQICgAAAA==.',
Eb='Ebtyrone:BAAANQAECgQIBAAAAA==.',
Em='Emmerson:BAAANQADCgQIBQAAAA==.Emphasis:BAAANQAECgEIAQABNQAECgkJHQAVAEoYAA==.',
Es='Escanór:BAAANQADCgUIBwAAAA==.',
Fa='Fajitajones:BAAANQADCgUICgAAAA==.',
Fo='Fooksdh:BAAANQADCggICgAAAA==.Fooksdk:BAABNQAECoEmAAMWAAgKkhe9KAAfAgAWAAgKkhe9KAAfAgADAAUKTweAhwC8AAAAAA==.Fooksdruid:BAAANQAECgQICAAAAA==.Forestpimp:BAAANQAECgQICQAAAA==.',
Fu='Fullometal:BAABNQAECoEaAAIQAAgKVRaeCwA8AgAQAAgKVRaeCwA8AgAAAA==.Furojin:BAAANQAECgUICQABNQAECgYIGwAGAH0LAA==.',
Ga='Galroot:BAABNQAECoEjAAINAAgK6yRoBgBKAwANAAgK6yRoBgBKAwAAAA==.Galstad:BAAANQABCgEIAQAAAA==.Garrett:BAAANQADCgEIAQAAAA==.',
Ge='Geff:BAAANQADCgQIBAAAAA==.',
Gh='Ghôst:BAAANQAECgMIAwABNQAFFAIIBAAFAAAAAA==.',
Gi='Girthhquake:BAAANQAECgQIBgAAAA==.Gisokaashi:BAAANQADCgcIEAAAAA==.',
Gn='Gnomepwner:BAAANQADCgcIBwAAAA==.',
Go='Gothick:BAAANQAECgQIBwAAAA==.',
Gr='Grimréaper:BAAANQADCgIIAgAAAA==.',
Gu='Guts:BAAANQAECgEIAQAAAA==.',
Ha='Harryhoudini:BAAANQAECgEJAQAAAA==.',
He='Healforfun:BAABNQAECoEoAAINAAgKxRp5FwBfAgANAAgKxRp5FwBfAgAAAA==.Heilung:BAABNQAECoEiAAQXAAkKcxM3CADrAQAXAAgKlRM3CADrAQALAAEK6ASXRwA3AAAUAAEKJwEUPwAdAAAAAA==.',
Hi='Hippokleides:BAAANQADCgYICgAAAA==.Hirradee:BAABNQAECoEoAAIJAAkKaxW+GgBmAgAJAAkKaxW+GgBmAgAAAA==.',
Ho='Holyzeal:BAAANQADCgUIBQAAAA==.Honatuto:BAAANQAECgQIBgAAAA==.',
Hu='Hubelez:BAABNQAECoEaAAIGAAkKCQ5mXQAzAgAGAAkKCQ5mXQAzAgAAAA==.',
Hy='Hyacine:BAAANQADCggIEAAAAA==.',
Ic='Icecweam:BAAANQADCggIDgAAAA==.Icthelight:BAAANQAECgMIAwAAAA==.',
Ig='Ightbet:BAAANQADCgEIAgAAAA==.',
Ii='Iista:BAAANQAECgEIAQAAAA==.',
Ir='Irontuskss:BAAANQAECgEIAQAAAA==.',
Iz='Iznthyr:BAAANQABCgIIAgAAAA==.',
Ja='Jayar:BAABNQAECoEdAAMVAAkKShj7GwCVAgAVAAkKShj7GwCVAgAYAAEKWQi7LgAkAAAAAA==.',
Jd='Jdawgg:BAAANQAECgEIAQAAAA==.',
Jo='Jorley:BAAANQADCggIDwAAAA==.',
Jr='Jrwriter:BAAANQAECgYIEAAAAA==.',
Jy='Jym:BAAANQAECgYICwAAAA==.',
Ka='Kaijin:BAABNQAECoEdAAISAAgKhhZyIQDyAQASAAgKhhZyIQDyAQAAAA==.Kalasting:BAAANQAECgMIBgABNQAECggIHAAZAPIeAA==.Kalyr:BAAANQAECgYIDwAAAA==.Kandrianna:BAABNQAECoEdAAIKAAgKwAV+NQBRAQAKAAgKwAV+NQBRAQAAAA==.',
Ke='Keraasi:BAABNQAECoEkAAMHAAgKrBZoPgBNAgAHAAgKrBZoPgBNAgABAAEKYwdSegExAAAAAA==.Kevinv:BAAANQADCgEIAQAAAA==.',
Kh='Khristine:BAAANQADCgQIBAABNQAECgkJHQAVAEoYAA==.',
Ki='Kikai:BAAANQADCgUICQAAAA==.Kilrav:BAABNQAECoEaAAIaAAcK/hroPQACAgAaAAcK/hroPQACAgAAAA==.Kimberlee:BAAANQAECggIDQAAAA==.Kiryanna:BAAANQAECgQIBQAAAA==.Kitiara:BAAANQAECgQJBAAAAA==.',
Kl='Klayah:BAAANQAECgQIDQAAAA==.',
Ko='Koogz:BAAANQAECgQICQAAAA==.Kordelia:BAABNQAECoEaAAIHAAcKchrMSgAdAgAHAAcKchrMSgAdAgABNQAECgcIHAAGALEcAA==.Korgmafx:BAAANQADCgUIEAAAAA==.',
Kr='Kratosol:BAAANQAECgEJAQAAAA==.',
Ku='Kudre:BAAANQABCgIIAgAAAA==.',
Ky='Kynigos:BAAANQADCggICAABNQAECgYIEgAFAAAAAA==.',
La='Larke:BAAANQAECgMIBgAAAA==.',
Le='Leilany:BAAANQAECgQIDAAAAA==.Lethäl:BAAANQADCgIIAgAAAA==.',
Li='Littledirk:BAAANQADCgcIAgAAAA==.',
Ll='Llillies:BAAANQAECgEIAQAAAA==.',
Lu='Lugnuts:BAAANQAECgQIBQAAAA==.',
Ma='Magebuff:BAABNQAECoEvAAIbAAkKmR9gMgAaAwAbAAkKmR9gMgAaAwAAAA==.Malroy:BAAANQADCgYIBgAAAA==.',
Mc='Mcheals:BAAANQADCgcIDgAAAA==.',
Mi='Miidniter:BAAANQAECgQICAAAAA==.',
Mo='Monsunami:BAAANQAECgQICAAAAA==.Moogar:BAABNQAECoEdAAMcAAgKliCQGQDwAgAcAAgKliCQGQDwAgAIAAEKuwObFgEyAAAAAA==.Moolinda:BAAANQAECgMIAwAAAA==.Moonlock:BAAANQADCggICAAAAA==.Morte:BAAANQADCgIIAgAAAA==.Moònflower:BAAANQAECgIIAgAAAA==.',
['Mø']='Møøse:BAABNQAECoEaAAIcAAgKGhyUMQB0AgAcAAgKGhyUMQB0AgAAAA==.',
Na='Namegoeshere:BAAANQAECgMIAwABNQAECgYIGwAGAH0LAA==.Nanwu:BAABNQAECoEcAAIIAAcKdxU1ZQDAAQAIAAcKdxU1ZQDAAQAAAA==.Narcyon:BAABNQAECoEcAAMZAAgK8h6qLACWAgAZAAgK8h6qLACWAgAKAAYK+A/dMwBcAQAAAA==.',
Ne='Neonfel:BAAANQADCggICAAAAA==.',
Nh='Nhox:BAAANQAECgQICQAAAA==.Nhöxx:BAAANQADCgUIBwAAAA==.',
No='Noobîtîs:BAAANQAECgMIAwAAAA==.Notmaxxie:BAAANQAECgMIBAAAAA==.',
Ny='Nystiae:BAAANQADCggICgAAAA==.',
Ob='Obz:BAAANQAECggIEwAAAA==.',
Od='Oddlylight:BAAANQAECgQICQAAAA==.',
Og='Ogzugz:BAAANQABCgUIBQAAAA==.',
Ol='Ollie:BAAANQADCgIIAgAAAA==.',
Ox='Oxytocin:BAAANQADCgIIAgAAAA==.',
Pa='Pandicated:BAEBNQAECoEoAAQSAAkKkBZmHQAeAgASAAkK1BFmHQAeAgAdAAcKNRRYEADDAQAeAAEKWwDbTwATAAAAAA==.',
Pe='Pelondar:BAAANQADCggIDgAAAA==.',
Ph='Phalanx:BAAANQADCgYIDwAAAA==.',
Pi='Pickleburger:BAAANQADCgUIBQAAAA==.',
Pl='Plaguedoctor:BAAANQADCgQJBAAAAA==.',
Po='Pookalicious:BAAANQADCgQIBAAAAA==.Pookiebear:BAAANQADCgIIAgAAAA==.Possessed:BAAANQADCgYICgAAAA==.',
Pr='Prìdè:BAAANQAECgcIEAAAAA==.',
Pu='Punjana:BAAANQABCgMIAwAAAA==.',
Ra='Raike:BAAANQADCgMIAwAAAA==.Razmae:BAAANQAECgMIAwAAAA==.',
Re='Rennala:BAAANQAECgEIAQAAAA==.',
Ri='Riceball:BAAANQADCgMIAwAAAA==.Riptide:BAABNQAECoEZAAIbAAgKpxGSqAAQAgAbAAgKpxGSqAAQAgAAAA==.Risto:BAAANQAECgYIEgAAAA==.',
Ro='Rockon:BAABNQAECoEbAAIIAAkKoQtoXwDUAQAIAAkKoQtoXwDUAQABNQADCgcIDgAFAAAAAA==.Roden:BAAANQABCgMIAwAAAA==.Ronzertnin:BAAANQAECgYIDQAAAA==.Roxen:BAAANQADCggIFQAAAA==.',
Ru='Runananako:BAAANQAECgQICgAAAA==.',
Ry='Ryo:BAAANQADCggICAAAAA==.',
['Ré']='Réaper:BAAANQADCgcIDwAAAA==.Rénji:BAABNQAECoEWAAISAAcKgA9wLQB6AQASAAcKgA9wLQB6AQAAAA==.',
Sa='Salana:BAAANQAECgMIBgAAAA==.San:BAABNQAECoEXAAMfAAkK8hxLEADeAgAfAAgKAx5LEADeAgAgAAIKrBNqFQB6AAABNQAFFAIIBgAZAHgOAA==.Sandroin:BAAANQAECgEIAQAAAA==.Sarah:BAAANQADCggIDAABNQAECgkJKgAZAFQkAA==.',
Sc='Scarf:BAABNQAECoEaAAMhAAgKDApMmQC0AQAhAAgKDApMmQC0AQAiAAEKWAMsQQAgAAAAAA==.',
Sh='Shiggy:BAAANQADCggICAAAAA==.Shinerbock:BAAANQAECgcIEwAAAA==.Shipoopi:BAAANQAECgYIEAAAAA==.Shock:BAABNQAECoEZAAIIAAgKTCInGAAiAwAIAAgKTCInGAAiAwAAAA==.Shortnshady:BAABNQAECoEaAAIjAAgKfw0QGQD/AQAjAAgKfw0QGQD/AQAAAA==.',
Si='Sithen:BAAANQAECgMIAwAAAA==.',
Sk='Skankadin:BAAANQADCgYICQABNQAECgIIBAAFAAAAAA==.Skankerella:BAAANQAECgIIBAAAAA==.Skiatrochia:BAAANQADCggICAABNQAECgkJKAAJAGsVAA==.Skipuscales:BAABNQAECoEdAAIUAAkKLSFjBABFAwAUAAkKLSFjBABFAwAAAA==.',
Sm='Smoaky:BAABNQAECoEgAAIQAAgKHgjKFQBlAQAQAAgKHgjKFQBlAQAAAA==.',
So='Soul:BAABNQAECoEsAAMMAAkKHB4sFAAQAwAMAAkKHB4sFAAQAwAkAAQKoQuMNgCoAAAAAA==.Soulscorcher:BAAANQADCggIFAAAAA==.Soulsurvivor:BAAANQAECgEIAQABNQAECgUIEAAFAAAAAA==.Sovietpanda:BAAANQADCgUICAAAAA==.',
Sp='Spanky:BAAANQAECgQIBgAAAA==.Spankyohs:BAAANQADCgcJDAAAAA==.Spindles:BAAANQAECgEIAQAAAA==.Spineless:BAAANQADCgQIBAAAAA==.Spiritgun:BAAANQAECgEIAQABNQAECgYIEAAFAAAAAA==.',
St='Stimpack:BAAANQAECgUIEAAAAA==.',
Su='Sutures:BAAANQADCgYIDgAAAA==.',
['Sö']='Sönja:BAAANQAECgIIBAAAAA==.',
Ta='Tacotuesday:BAAANQABCgcIBwAAAA==.Tará:BAAANQAECgUJCQAAAA==.',
Te='Techpriest:BAAANQAECgMIAgAAAA==.Tehblink:BAABNQAECoEcAAIlAAcK+R1wBgBvAgAlAAcK+R1wBgBvAgAAAA==.Tenative:BAAANQAECgIIAwABNQAECgkJIQAOAHYgAA==.Tenoch:BAAANQAECgUIDAAAAA==.Terah:BAAANQADCgIIAgAAAA==.',
To='Tobibobi:BAAANQADCgUIBQAAAA==.Toomez:BAAANQADCggICgAAAA==.Touchmydemon:BAAANQAECgUICgAAAA==.',
Tr='Trea:BAABNQAECoEaAAIGAAcKKRMngQDbAQAGAAcKKRMngQDbAQAAAA==.',
Tu='Tupkiss:BAABNQAECoEiAAIKAAgKcB/NEADSAgAKAAgKcB/NEADSAgAAAA==.',
Ty='Tygrand:BAAANQAECgEIAQABNQAECggIIAAQAB4IAA==.',
Va='Vazer:BAAANQABCgMIAwAAAA==.',
Vo='Voidtouched:BAAANQADCggICAAAAA==.',
Wa='Waffledead:BAABNQAECoEhAAQmAAgKAR3rBwDyAQAmAAYKqxvrBwDyAQAOAAUKLRoUogBiAQAPAAQKtxsiJABHAQAAAA==.Wafflelight:BAAANQADCgcIBwAAAA==.Warpfiend:BAAANQAECgYIEQAAAA==.',
We='Wek:BAAANQADCgUIBQAAAA==.Wetnugget:BAAANQAECgEIAgAAAA==.',
Wi='Winnie:BAAANQADCgEIAQAAAA==.',
Wo='Wolfnhowz:BAAANQAECgIIAgAAAA==.',
Wy='Wyhm:BAAANQADCgIIAgAAAA==.',
Yu='Yuriko:BAAANQADCgYIDAAAAA==.',
Za='Zandragon:BAAANQADCgQIBAAAAA==.',
Ze='Zebubblez:BAAANQAECgIIAwAAAA==.',
Zg='Zgux:BAAANQAECgQIBwAAAA==.',
Zo='Zoêy:BAAANQADCggIHQAAAA==.',
Zu='Zuraki:BAAANQAECgQIBgAAAA==.',
Zz='Zzin:BAAANQABCgEIAQAAAA==.',
['Ço']='Çountèr:BAAANQAECgIIAgAAAA==.',
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
