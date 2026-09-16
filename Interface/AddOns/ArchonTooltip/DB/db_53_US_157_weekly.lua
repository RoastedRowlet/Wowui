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

local lookup = {'Unknown-Unknown','Monk-Windwalker','Druid-Balance','Hunter-Marksmanship','Warrior-Arms','Shaman-Enhancement','Priest-Holy','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Discipline','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Shaman-Elemental','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Shaman-Restoration','Priest-Shadow','DeathKnight-Blood','Hunter-BeastMastery',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaralia:BAAANQAECgUICgAAAA==.',
Ab='Abyssdark:BAAANQAECgUICwAAAA==.',
Ac='Accusation:BAAANQAECggIBwAAAA==.',
Ak='Akadeus:BAAANQADCggICgAAAA==.',
Al='Alarielle:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.',
Am='Amirah:BAAANQADCgEIAQAAAA==.',
An='Anamarie:BAAANQAECgQIBQAAAA==.',
Ar='Aramist:BAAANQADCgQIBAAAAA==.Arroy:BAAANQADCgcIDAAAAA==.',
As='Ashikahammer:BAAANQADCgMIBAABNQAECgcIEwABAAAAAA==.',
Ba='Baehyun:BAAANQAECggIDQABNQAFFAYIDQACAL0fAA==.',
Bl='Bloodbeard:BAAANQAECgMIBAAAAA==.Bloodedge:BAAANQADCgIIAgAAAA==.',
Bo='Bohmbear:BAAANQADCgYIBgAAAA==.',
Br='Brentobox:BAAANQAECgEIAQAAAA==.Brugara:BAAANQADCgUICAAAAA==.',
Ca='Camael:BAAANQAECgIIAwAAAA==.Cannelle:BAAANQADCgcICQAAAA==.Carden:BAAANQAECgEIAQAAAA==.',
Ce='Cervantes:BAAANQADCgcIFQAAAA==.',
Ch='Chardr:BAACNQAFFIEGAAIDAAUJEQsrBACDAQADAAUJEQsrBACDAQA1AAQKgRgAAgMACAn0IrAOAP8CAAMACAn0IrAOAP8CAAAA.Chillywillie:BAAANQADCgcIGQAAAA==.Chrodne:BAAANQADCgQICAAAAA==.Chucknorrîs:BAAANQADCggIDgAAAA==.',
Cl='Clintbarton:BAABNQAECoEZAAIEAAYJJgnBKAAsAQAEAAYJJgnBKAAsAQAAAA==.',
Cr='Crûtch:BAAANQADCggIDQAAAA==.',
Ct='Cthullu:BAAANQADCggICAAAAA==.',
Cu='Culebra:BAAANQAECgUIDwAAAA==.',
['Cø']='Cøldshoulder:BAAANQAECgUICQAAAA==.',
Da='Daehyun:BAAANQADCgcIAwABNQAFFAYIDQACAL0fAA==.Danceofdeath:BAAANQAECgEIAQABNQAECgcIFQAFAHoeAA==.Dane:BAAANQAECgYIBwAAAA==.Darcmatter:BAAANQAECgYICgAAAA==.',
De='Deadtrap:BAAANQABCgcIDAAAAA==.Deathsend:BAAANQADCgYICAAAAA==.Deepsicks:BAABNQAECoEVAAIGAAkJqRW6BQC/AgAGAAkJqRW6BQC/AgAAAA==.Deepstate:BAAANQADCgYIEgAAAA==.Demonäde:BAAANQADCgUIAgAAAA==.',
Di='Dima:BAAANQAECgUICgAAAA==.Dithy:BAAANQADCgcIFwAAAA==.',
Dk='Dkrmk:BAAANQADCgMIAgAAAA==.',
Dn='Dne:BAAANQADCggICAABNQAECgYIBwABAAAAAA==.',
Do='Donavon:BAAANQAECgIIAwAAAA==.Donutjelly:BAAANQAECgMIBAAAAA==.Dornnbryda:BAAANQADCggIDgABNQAECgIIAwABAAAAAA==.',
Dr='Drackothyr:BAAANQAECgIIAwAAAA==.Drumark:BAAANQADCgMIAwAAAA==.',
Dw='Dwastring:BAAANQAECgMIAwAAAA==.',
Dy='Dyrale:BAAANQADCgYIEQAAAA==.',
Ek='Eknivar:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.',
Er='Erebus:BAAANQAECgQIBAAAAA==.Erragorn:BAAANQAECgEIAgAAAA==.',
Ev='Evisa:BAAANQADCgcIDgAAAA==.Evokholio:BAAANQADCgcIFQAAAA==.',
['Eö']='Eöath:BAAANQAECgEIAQAAAA==.',
Fa='Falaurenta:BAAANQADCgMIBgAAAA==.',
Fe='Feidao:BAAANQADCggIHAAAAA==.Feralith:BAAANQADCgMIAQAAAA==.',
Fo='Foshizzle:BAAANQABCgIIAgAAAA==.',
['Fë']='Fëânòr:BAAANQADCgUIBQAAAA==.',
Ga='Gailinn:BAAANQAECgIIAgAAAA==.',
Go='Gorash:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.',
Gr='Greggdshami:BAAANQAECgQIBgAAAA==.',
Gu='Gundamus:BAAANQADCgYIBgAAAA==.',
He='Healmonger:BAAANQAECgcIDgAAAA==.Heruin:BAAANQAECgQIBwAAAA==.',
Hi='Hictor:BAAANQADCgMIAwAAAA==.',
Ho='Holly:BAAANQADCgEIAQAAAA==.Horse:BAABNQAECoEhAAIHAAkJPQrHMgDWAQAHAAkJPQrHMgDWAQAAAA==.Hourzero:BAAANQAECgEIAQAAAA==.',
Ia='Iammyscars:BAAANQAFFAEIAQAAAA==.',
Ic='Icu:BAAANQADCggICgAAAA==.',
Il='Ilovecheetos:BAAANQADCggIDgAAAA==.',
Ja='Jasnahh:BAAANQAECgQICQABNQAECgYICgABAAAAAA==.Jaylas:BAAANQADCgEIAQABNQAECgcIGgAIAPUVAA==.',
Jo='Joeexotíc:BAAANQADCgUIBQAAAA==.',
Ju='Jun:BAABNQAECoEhAAMJAAkJPyZwAAD6AwAJAAkJPyZwAAD6AwAKAAgJpSL+DADIAgAAAA==.',
Ka='Kasumaus:BAAANQAECgEIAQAAAA==.',
Ke='Kelly:BAAANQADCggICAAAAA==.Kennifer:BAAANQADCggICQAAAA==.Kenshindune:BAAANQADCgQIBAAAAA==.Keragan:BAAANQADCgEIAQAAAA==.',
Kh='Khalyeesi:BAAANQADCgIIAwAAAA==.Khandris:BAAANQABCgYIDgAAAA==.Khazjek:BAAANQADCgYICAAAAA==.Khephris:BAAANQAECgYICgAAAA==.',
Kn='Knivex:BAAANQAECgUICgAAAA==.',
Ko='Koryann:BAAANQAECgUICgAAAA==.Kova:BAAANQAECgEIAQAAAA==.',
Kw='Kwarthil:BAAANQABCgEIAQAAAA==.',
Ky='Kyrise:BAAANQABCgUIBQAAAA==.',
La='Lambo:BAAANQADCggICAAAAA==.Landam:BAAANQADCgcIGAAAAA==.',
Le='Leap:BAAANQADCgMIAwABNQAECgQICQABAAAAAA==.',
Li='Lifeaura:BAABNQAECoEhAAILAAkJoRtgAQDvAgALAAkJoRtgAQDvAgAAAA==.Lightbläster:BAAANQAECgIIAwAAAA==.Lightrider:BAAANQADCgYICwAAAA==.Linesta:BAAANQADCgEIAQAAAA==.Lionroar:BAABNQAECoEeAAIMAAkJCCPRAQB/AwAMAAkJCCPRAQB/AwAAAA==.Littleguy:BAAANQAECgQIBgAAAA==.',
Ll='Llaothtaed:BAAANQADCgYICwAAAA==.',
Lo='Lochannis:BAAANQADCggIEAAAAA==.Lokalock:BAAANQADCgQIBAABNQAECgkJGwAGABAcAA==.Lonee:BAAANQADCgIIAgAAAA==.Lorellei:BAAANQAECgEIAQAAAA==.',
Ma='Manticor:BAAANQADCgcIBgAAAA==.Martyglaive:BAAANQAECgQIBQAAAA==.Matteas:BAAANQAECgUICgAAAA==.',
Me='Mew:BAAANQAECgQIBgAAAA==.',
Mf='Mfdoom:BAABNQAECoEaAAQNAAkJhBfSJgBKAgANAAgJrRTSJgBKAgAOAAMJaxOpMQDHAAAPAAIJ/RloEACGAAABNQADCgIIAgABAAAAAA==.',
Mi='Mizrey:BAAANQAECggIAQAAAA==.',
Mo='Mograins:BAAANQAECgUIEAAAAA==.Monzcarro:BAAANQADCggICwAAAA==.Morgainne:BAAANQADCgcIFwAAAA==.Mortmor:BAAANQADCggICAAAAA==.',
Mu='Muffinn:BAAANQAECgYIEAAAAA==.',
My='Mymdos:BAAANQAECgcIEAABNQABCgIIAgABAAAAAA==.Myrmidonn:BAAANQADCgYICgAAAA==.',
['Mä']='Mästérdòn:BAAANQADCgMIAwAAAA==.',
['Må']='Måsterdon:BAAANQAECgQICAAAAA==.',
Ne='Nercos:BAAANQAECgEIAQABNQAFFAIIAgABAAAAAA==.Nercqt:BAAANQAFFAIIAgAAAA==.Neverborn:BAAANQAECgQIBAAAAA==.',
Ni='Niame:BAAANQADCgQICwAAAA==.Nitraina:BAAANQAECgMIBQAAAA==.Niyabelle:BAAANQAECgYIDAAAAA==.',
Ny='Nyxth:BAAANQABCgQIBAAAAA==.',
Od='Odïn:BAAANQADCgYIBwAAAA==.',
Ol='Oleevia:BAAANQAECgYIDgAAAA==.',
Om='Omgdingers:BAAANQAECgYICAAAAA==.',
On='Oneshót:BAAANQADCgIIAgABNQAECgcICgABAAAAAA==.Oneth:BAAANQADCgcIFAAAAA==.',
Or='Oraxia:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Orgdynamite:BAAANQAECgEIAQABNQAECgkJIQAQAHwgAA==.Orgsham:BAABNQAECoEhAAMQAAkJfCBuCgBKAwAQAAkJfCBuCgBKAwAGAAEJaw5AHgBMAAABNQAECgkJIQAQAHwgAA==.',
Pa='Paedragon:BAAANQADCgMIAwABNQADCgcIFAABAAAAAA==.Paladareian:BAABNQAECoEaAAIIAAcJ9RUMMAAEAgAIAAcJ9RUMMAAEAgAAAA==.',
Pe='Pej:BAABNQAECoElAAQRAAkJ3RzUCACCAgARAAgJhx7UCACCAgASAAQJIhKWIAD/AAATAAEJjw9ZEgBFAAAAAA==.Pejbolt:BAAANQADCgcICgABNQAECgkJIQAJAD8mAA==.',
Ph='Phoenixa:BAAANQADCggICAAAAA==.',
Pl='Plus:BAAANQAECgcICwAAAA==.',
Po='Powerslavé:BAABNQAECoEVAAIFAAcJeh7RNABnAgAFAAcJeh7RNABnAgAAAA==.',
Pr='Priestitoot:BAAANQADCgYICwAAAA==.',
Pu='Pumkinhead:BAAANQAECggIEwAAAA==.',
Py='Pyromania:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.',
['Pä']='Pä:BAAANQADCgMIAQAAAA==.',
Ra='Raiden:BAAANQAECgMIBAAAAA==.Rat:BAAANQABCgIIAgAAAA==.',
Ro='Rogi:BAAANQABCgYICgABNQABCgIIAgABAAAAAA==.',
['Rö']='Römana:BAAANQAECgQIBgAAAA==.',
Sa='Saliva:BAAANQADCggICAAAAA==.Sanguinaris:BAAANQAECgEIAQAAAA==.Sareya:BAAANQABCgYIDgAAAA==.Satyrical:BAAANQAECgMIBQAAAA==.',
Sc='Scorch:BAAANQAECgUICgAAAA==.',
Se='Selystine:BAAANQADCgUICAAAAA==.',
Sh='Shamwowolio:BAAANQAECgYIDAAAAA==.Shayd:BAAANQAECgYIDQAAAA==.Shirokyu:BAAANQADCggICAAAAA==.Shirraz:BAAANQAECgEIAQAAAA==.Shroomicide:BAAANQAECggIBgAAAA==.',
Si='Sicaris:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Sicksdeep:BAABNQAECoEXAAIFAAgJ2RLJRgAYAgAFAAgJ2RLJRgAYAgAAAA==.Sigürd:BAAANQADCgEIAQAAAA==.Silverstorm:BAAANQABCgcIDQAAAA==.',
Sk='Skÿe:BAAANQAECgQIBgAAAA==.',
Sl='Slamma:BAABNQAECoEiAAIFAAkJzCXXAgDRAwAFAAkJzCXXAgDRAwAAAA==.Slicedbreád:BAABNQAECoEeAAIUAAkJwhh8HAB1AgAUAAkJwhh8HAB1AgAAAA==.',
Sm='Smokadaganga:BAAANQAECgQIBwAAAA==.',
So='Sols:BAAANQADCggIDgABNQAECgcIFQAFAHoeAA==.Sondirion:BAAANQAECgIIAwAAAA==.Sowet:BAAANQADCgcIBwAAAA==.',
Sp='Speoghii:BAAANQAECgMICAAAAA==.Spifftreebug:BAAANQAECgQIBgAAAA==.Sprinklez:BAAANQADCgUICgAAAA==.',
St='Steelerschic:BAAANQADCggIGQAAAA==.Stormleader:BAAANQAECgcICgAAAA==.',
Su='Surge:BAAANQADCgYIFQAAAA==.',
Ta='Tai:BAAANQAECgQIBgAAAA==.Tainema:BAAANQAECgIIBAAAAA==.Tankguywowie:BAAANQAECgUIBQABNQAECgcIDQABAAAAAA==.Taurriel:BAAANQAECgUICgAAAA==.Tazzm:BAAANQAECgQICQAAAA==.',
Te='Teranok:BAAANQAECgUICAAAAA==.Terzal:BAAANQADCgYIBgAAAA==.',
Th='Thalel:BAAANQAECgIIAQAAAA==.Theacused:BAAANQAECgYIBwABNQAECggIBwABAAAAAA==.Thoir:BAABNQAECoEhAAIUAAkJGiWsAgCaAwAUAAkJGiWsAgCaAwABNQAECgkJIQAHAD0KAA==.',
Ti='Tipsylorcet:BAAANQAECgIIAwAAAA==.',
Tk='Tkrain:BAAANQADCgQIBAAAAA==.',
Tr='Tricktickler:BAAANQADCgcIFwAAAA==.Troy:BAAANQADCgUIBQAAAA==.',
Tu='Tuskani:BAAANQABCggICgAAAA==.',
Ty='Tybird:BAAANQAECgQIBwAAAA==.',
Ul='Ulsull:BAAANQADCgcIEAAAAA==.Ulyssi:BAABNQAECoEhAAIVAAkJYCAfBQBYAwAVAAkJYCAfBQBYAwAAAA==.',
['Uñ']='Uñàble:BAAANQADCgIIAgAAAA==.',
Va='Valymus:BAAANQADCgIIAgABNQAECgYIDQABAAAAAA==.Vandagylon:BAAANQADCgYIDAAAAA==.Vandals:BAAANQAECgQICQAAAA==.',
Ve='Ven:BAAANQAECgIIAwAAAA==.',
Vo='Voltaire:BAAANQADCgIIAgAAAA==.',
Wa='Walle:BAAANQADCgEIAQAAAA==.Wankstar:BAAANQAECgEIAQAAAA==.Warvein:BAAANQAECgMIAwAAAA==.',
We='Weehunt:BAAANQAECgEIAgAAAA==.',
Wh='Whillia:BAAANQADCgMIAwAAAA==.',
Wi='Wicah:BAAANQAECgEIAQAAAA==.Wicka:BAAANQAECgQICAAAAA==.Widowblade:BAAANQADCggICAAAAA==.Wildriver:BAAANQAECgEIAQAAAA==.',
Xa='Xaehyun:BAACNQAFFIENAAICAAYJvR+gAQDFAQACAAYJvR+gAQDFAQA1AAQKgRUAAgIACQmeJAgJAMwCAAIACQmeJAgJAMwCAAAA.Xandrelar:BAAANQADCggIDQABNQAECgYIDQABAAAAAA==.',
Xm='Xmrpdk:BAABNQAECoEhAAIWAAkJiiMkBACFAwAWAAkJiiMkBACFAwAAAA==.Xmrppally:BAAANQADCgQIBAABNQAECgkJIQAWAIojAA==.',
Xy='Xy:BAAANQADCggICAAAAA==.',
Ya='Yarina:BAAANQADCgUIBQAAAA==.',
Yo='Yoyiek:BAAANQAECgcIDQAAAA==.',
Za='Zalynn:BAAANQAECgEIAQAAAA==.Zanne:BAAANQAECgcIEwAAAA==.Zarthul:BAAANQAECgEIAgAAAA==.',
Zh='Zhenyu:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Zl='Zlot:BAEBNQAECoEhAAMXAAkJIiLmGgCnAgAXAAcJhyPmGgCnAgAEAAcJfRz1FgAeAgAAAA==.',
Zu='Zulani:BAAANQADCgIIAgAAAA==.',
['Õn']='Õneshot:BAAANQAECgcICgAAAA==.',
['Øñ']='Øñêshot:BAAANQADCggIEwABNQAECgcICgABAAAAAA==.',
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
