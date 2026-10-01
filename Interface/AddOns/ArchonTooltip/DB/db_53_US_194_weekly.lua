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

local lookup = {'Paladin-Holy','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Mage-Arcane','Mage-Frost','Mage-Fire','Druid-Balance','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Druid-Feral','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Warrior-Arms','Warrior-Protection','Shaman-Elemental','Priest-Shadow','Priest-Discipline',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-09-29',data={Ae='Aelita:BAAANQAECgUIDQAAAA==.',
Af='Afflicted:BAAANQAECgcIEAAAAA==.',
Ag='Agarne:BAAANQAECgQICQAAAA==.',
Ai='Aimster:BAAANQADCgQIBAAAAA==.',
Ak='Akhta:BAABNQAECoEaAAIBAAgKpCPwDQA5AwABAAgKpCPwDQA5AwAAAA==.',
Al='Allaris:BAAANQAECgUIDAAAAA==.Allíesin:BAAANQADCgcIEAAAAA==.Altryn:BAAANQABCgQIBAAAAA==.Alundrablaze:BAABNQAECoEfAAICAAgKQhnYLwBgAgACAAgKQhnYLwBgAgAAAA==.Alzynia:BAAANQABCgIIAgAAAA==.',
Am='Amarixa:BAAANQADCgQIBgABNQAECgQIBAADAAAAAA==.Amzng:BAAANQABCggJDQAAAA==.',
An='Ancecile:BAAANQADCgQIBAAAAA==.Anoint:BAAANQADCgQIBAABNQAECgkJKgAEALciAA==.Anrraakk:BAAANQADCgYIBgAAAA==.Antonello:BAAANQADCgcIBwAAAA==.',
Ar='Aranthino:BAAANQAECgYIEQAAAA==.Arnzul:BAAANQAECgUICwAAAA==.Aryabhatta:BAAANQAECgUIDwAAAA==.',
As='Asakura:BAABNQAECoEbAAIFAAgKpRjiLgAaAgAFAAgKpRjiLgAaAgAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.',
Ba='Ballrogg:BAAANQADCgIIAgAAAA==.Bamdk:BAABNQAECoEiAAMGAAgKEx5FKwAyAgAGAAgK6RlFKwAyAgAFAAcKbhOQRACmAQAAAA==.Bamshambam:BAAANQAECgYIEgABNQAECggIIgAGABMeAA==.Baoshengdadi:BAAANQADCgMIAwABNQAECgkJIgACAJ0eAA==.',
Be='Beansfu:BAAANQAECgYIEgABNQAECgcIEAADAAAAAA==.Beansinator:BAAANQAECgcIEAAAAA==.Beefsupriem:BAAANQAECgUIEAAAAA==.Bellatrïx:BAAANQADCgcIHAABNQADCgcIEAADAAAAAA==.Belliaz:BAAANQAECgQIBAAAAA==.',
Bg='Bgwinnier:BAAANQADCgYIBgAAAA==.',
Bi='Bialar:BAAANQADCgcIDQAAAA==.Bigchéésé:BAAANQAECgQIBAAAAA==.Biteme:BAAANQABCgIJAgAAAA==.',
Bl='Blackforge:BAAANQABCgMIAwAAAA==.Bloodwell:BAAANQAECgUIDgAAAA==.',
Bo='Bovinar:BAAANQAECgQIBwAAAA==.',
Br='Bruzera:BAAANQAECgUICQAAAA==.',
Bu='Bulldan:BAAANQAECgUIDwAAAA==.Buzrkk:BAAANQAECgYICwAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
['Bò']='Bòóberry:BAAANQADCgYIBgAAAA==.',
Ca='Candyquartz:BAAANQAECgEIAQAAAA==.Captaïn:BAAANQAECgIIAgAAAA==.',
Ce='Celladorne:BAAANQADCggIGAAAAA==.',
Cg='Cg:BAABNQAECoEeAAIHAAkKTxpIRwDRAgAHAAkKTxpIRwDRAgAAAA==.',
Ch='Chibi:BAAANQAECgEIAgAAAA==.Chrent:BAAANQAECgIIAgAAAA==.Chronokite:BAAANQAECgQIBgAAAA==.',
Cl='Clawburr:BAAANQADCgQIBwABNQAECgEIAQADAAAAAA==.Clelronah:BAAANQADCgYIBwAAAA==.',
Cy='Cybele:BAAANQADCggIBgABNQAECgQIBgADAAAAAA==.',
Da='Dalmaar:BAAANQABCgEIAQAAAA==.Dantae:BAAANQADCgYICQAAAA==.Darafragen:BAABNQAECoEbAAIBAAgKWRYNPQAwAgABAAgKWRYNPQAwAgAAAA==.',
De='Deader:BAAANQAECgMIBgAAAA==.Demonseed:BAAANQADCgYJBgAAAA==.Demonslice:BAAANQAECgIIAgAAAA==.Dentarus:BAAANQADCggICAAAAA==.',
Di='Disengage:BAAANQAECgEIAQAAAA==.Displace:BAAANQAECgEIAQAAAA==.Divinewords:BAAANQAECgYICgAAAA==.Divish:BAAANQAECgUIBwAAAA==.',
Dk='Dkramm:BAAANQAECgYIDQAAAA==.',
Do='Donhector:BAABNQAECoEfAAIGAAgKDRdrLwAXAgAGAAgKDRdrLwAXAgAAAA==.Dontsheep:BAAANQAECgUICQAAAA==.Dorim:BAAANQADCgYIBgAAAA==.Doubl:BAAANQAECgEIAgAAAA==.',
Dr='Dracowarrior:BAAANQADCgQJBAAAAA==.Drak:BAAANQADCgYIBgAAAA==.Dreannaog:BAAANQADCgYIBgAAAA==.Dreyvia:BAAANQADCgYICgAAAA==.Druecc:BAAANQAECgUIDwAAAA==.Druidlord:BAAANQAECgQICQAAAA==.Druidpeng:BAAANQADCgUIBQAAAA==.',
Du='Dudeimpriest:BAAANQADCgUIBQAAAA==.Dundalo:BAAANQADCgYIBgAAAA==.',
['Då']='Dågon:BAAANQAECgEIAQAAAA==.',
El='Elchaman:BAAANQAECgEIAQAAAA==.Elcuh:BAAANQAECgEIAQAAAA==.Ellennia:BAAANQAECgEIAQAAAA==.Ellisandré:BAABNQAECoEjAAQHAAkKFR5/OQD2AgAHAAkKlRx/OQD2AgAIAAMKGiARFQAZAQAJAAEKnhPPCABJAAAAAA==.',
En='Endra:BAAANQADCgIIAgABNQAECgcIEAADAAAAAA==.',
Er='Era:BAAANQAECgIIAgAAAA==.',
Es='Esh:BAAANQAECgUIBQABNQAECgcIDwADAAAAAA==.',
Ev='Evilinside:BAAANQADCgYIBgAAAA==.',
Fa='Fanara:BAAANQADCgUIBQAAAA==.Farty:BAAANQAECgIIBgAAAA==.',
Fi='Fianchetto:BAAANQABCgIIAgAAAA==.Fitua:BAAANQADCggICAAAAA==.Fizzbann:BAAANQABCgIIAgABNQAECgIIAgADAAAAAA==.',
Fo='Fortytwö:BAAANQAECgQICQAAAA==.Foutre:BAAANQAECgUICwAAAA==.',
Fr='Fruntstabba:BAAANQAECgEIAQAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBQAAAA==.Fungus:BAABNQAECoEoAAMKAAkKfiXfAgDCAwAKAAkKfiXfAgDCAwAEAAIKISVGJgDYAAAAAA==.Fuzzytotems:BAAANQADCggIEQAAAA==.',
Fy='Fynnick:BAAANQAECgQIBAAAAA==.',
Ga='Gaar:BAAANQAECgEIAQAAAA==.Galgar:BAAANQAECgYIDAAAAA==.',
Ge='Getlnmyvan:BAAANQAECgcIEgAAAA==.',
Gh='Ghoulgranny:BAAANQADCgcICgAAAA==.',
Gi='Gile:BAAANQADCgYIBgABNQADCggICAADAAAAAA==.',
Gl='Glert:BAAANQAECgQIAQAAAA==.Glorp:BAAANQAECgIIAgAAAA==.',
Go='Goinmonk:BAAANQADCgYICgAAAA==.Goinsolo:BAABNQAECoEaAAILAAgK/gsWagDmAQALAAgK/gsWagDmAQAAAA==.Gorvax:BAAANQAECgUIDwAAAA==.Gozz:BAAANQABCgQIBQAAAA==.',
Gr='Grglmrglmrgl:BAAANQABCgIIAgAAAA==.Grimlóck:BAAANQAECgMIBgAAAA==.Grumok:BAAANQABCgQIBQAAAA==.',
Gw='Gwenledyr:BAABNQAECoEcAAQMAAgKYxIlDQA5AQAMAAUKvRAlDQA5AQANAAMKKRJv0gC/AAAOAAMK2g1KQACtAAAAAA==.Gwynhria:BAAANQAECgQIBAAAAA==.',
Ha='Hallebearie:BAAANQAECgQIBgABNQADCgIIAgADAAAAAA==.',
He='Heathèn:BAAANQAECgQIBQAAAA==.Heimthrall:BAAANQAECgUIBQAAAA==.Hekus:BAEBNQAECoEcAAIPAAkKDRWTYQAdAgAPAAkKDRWTYQAdAgAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Horohöro:BAABNQAECoEqAAIEAAkKtyIGAgCIAwAEAAkKtyIGAgCIAwAAAA==.',
Hu='Hugme:BAAANQADCgYIBgABNQAECgUIDwADAAAAAA==.Hukari:BAAANQADCgQIBAABNQAFFAUICQAQAHwQAA==.Hunpath:BAAANQAECgcIDQAAAA==.',
['Hà']='Hàwk:BAAANQADCgYIBgAAAA==.',
Ic='Icelynn:BAAANQAECggIEwABNQAFFAIIBQALAHQXAA==.',
Ii='Iiambloody:BAAANQADCgQIBAAAAA==.Iil:BAAANQAECgIIAgAAAA==.',
Iq='Iqsamurai:BAAANQABCgYIBgAAAA==.',
It='Itruszia:BAAANQAECgQICAAAAA==.',
Ja='Jalir:BAAANQABCgMIAwAAAA==.Jaquavius:BAAANQADCgMIAwABNQAECgcIEAADAAAAAA==.Jaxxia:BAAANQAECgIIAwABNQAECgUIEgADAAAAAA==.',
Jb='Jblaze:BAAANQAECgUIBQAAAA==.',
Jh='Jhalicistu:BAAANQAECgMIBAAAAA==.',
Ju='Juzodots:BAAANQADCgUIBQAAAA==.Juzomido:BAABNQAECoEkAAIRAAkKjiBYAgDnAgARAAkKjiBYAgDnAgAAAA==.',
Ka='Kaijhin:BAAANQAECgYIEgAAAA==.Kaline:BAAANQAECgIIAgAAAA==.Katianna:BAABNQAECoEcAAICAAgKLBvHMwBMAgACAAgKLBvHMwBMAgAAAA==.',
Ke='Keallach:BAAANQAECgYIEgAAAA==.Kelanath:BAAANQAECgUIDwAAAA==.',
Kh='Khalli:BAAANQAECgUIEQAAAA==.Khaps:BAAANQADCgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.Khora:BAAANQADCgYIBgAAAA==.',
Ki='Kiffprime:BAAANQADCgYICgAAAA==.Kittycatlj:BAAANQADCggIEQAAAA==.Kiyosara:BAAANQADCgYJCgAAAA==.Kizent:BAAANQADCggICAAAAA==.',
Kr='Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQADCggIDAAAAA==.',
Ku='Kulrig:BAAANQADCgYIDAAAAA==.Kurri:BAAANQADCgYIHAAAAA==.',
La='Larde:BAAANQADCgcJEAABNQADCgYIDAADAAAAAA==.',
Li='Lightjohn:BAAANQADCgEJAQABNQADCggIEQADAAAAAA==.',
Lo='Loakal:BAAANQADCgQIBAAAAA==.Lovemarauder:BAAANQADCgYJBgAAAA==.',
Lu='Lunaari:BAAANQAECgUIDwAAAA==.Lurarind:BAAANQAECgcIEgAAAA==.',
['Lè']='Lègendary:BAAANQADCgQIBAABNQAECgQICQADAAAAAA==.',
Ma='Maeday:BAAANQADCgQIBAAAAA==.Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAAANQAECgcICwAAAA==.Malganon:BAAANQAECgUICgAAAA==.Malygoz:BAAANQAECgEIAQABNQAECgkJNQAPAMciAA==.Martheiran:BAAANQAECgYIEwAAAA==.Mashpewtater:BAAANQAECgEIAQAAAA==.Mashpwntato:BAAANQAECgQIBAAAAA==.Mathelmana:BAAANQAECgUIEAABNQAECggIHwACAEIZAA==.Mawika:BAAANQADCggJEgAAAA==.',
Mc='Mcbdeath:BAAANQADCggICAABNQAECgIIBgADAAAAAA==.',
Me='Mechafour:BAAANQAECgUICgAAAA==.Medusaa:BAAANQAECgIIAgAAAA==.',
Mi='Miliandra:BAAANQADCgUIAQAAAA==.Minervasande:BAAANQADCgMIAwAAAA==.Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAABNQAECoEmAAISAAkKnhZGGwB5AgASAAkKnhZGGwB5AgAAAA==.Missfrost:BAAANQADCgMIAwAAAA==.Mistickay:BAAANQAECgIIAgAAAA==.Mizbeheaven:BAAANQADCgMJAwABNQAECgQIBAADAAAAAA==.',
Mo='Moreblood:BAAANQAECgYIDQAAAA==.Morghella:BAABNQAECoEXAAILAAcKIBRmaADrAQALAAcKIBRmaADrAQAAAA==.Morhsa:BAAANQABCgMIAwAAAA==.Moána:BAAANQADCgMIAwAAAA==.',
Mu='Murtaugh:BAAANQABCgQIBAAAAA==.',
Mw='Mw:BAAANQAECgcIDwAAAA==.',
My='Mynadshealu:BAAANQADCgEIAQAAAA==.Mysticbrew:BAAANQAECgUICgAAAA==.Mythros:BAAANQAECgIIAwAAAA==.',
Na='Nations:BAAANQABCgIIAgAAAA==.',
Ne='Nezalan:BAAANQADCgUIBQABNQAECggIIAAIAKgbAA==.',
Ni='Nightwitch:BAAANQADCgYIDAAAAA==.',
No='Noirra:BAABNQAECoEoAAILAAgKZRt2NQCHAgALAAgKZRt2NQCHAgAAAA==.Noxxival:BAAANQADCgUIBQAAAA==.',
Om='Omusa:BAAANQAECgQIBAAAAA==.',
Or='Orcnick:BAAANQADCgcIEQAAAA==.',
Ov='Overfrosty:BAAANQAECgUIEAAAAA==.Overhealin:BAAANQADCgIIAgAAAA==.',
Oz='Ozaí:BAAANQADCgMIBAAAAA==.',
Pe='Peng:BAAANQAECgEIAQAAAA==.Pesto:BAAANQAECgQICAAAAA==.',
Pi='Pinenuts:BAAANQABCgQIBgAAAA==.',
Ps='Psyberollin:BAAANQADCggICAAAAA==.',
Pu='Purgedfire:BAAANQADCgUICQAAAA==.',
Ra='Ratings:BAAANQAECgEIAQAAAA==.Rayda:BAAANQAECgIIBgAAAA==.',
Re='Reighan:BAAANQADCggIGQAAAA==.Renka:BAAANQAECgUICQAAAA==.Revolting:BAABNQAECoEeAAITAAkK+h2qDQDsAgATAAkK+h2qDQDsAgAAAA==.Rezme:BAAANQADCgYIBgAAAA==.',
Ri='Rianne:BAAANQAECgUIDgAAAA==.',
Ro='Rowanbow:BAAANQAECgEIAQAAAA==.',
['Ré']='Rédd:BAAANQAECgYICQAAAA==.',
Sa='Saberhawk:BAAANQAECgEIAgAAAA==.Sakurazuka:BAAANQAECgQIDQAAAA==.Sanath:BAABNQAECoEYAAMUAAgKjAouCgB3AQAUAAgKjAouCgB3AQAVAAIKGQFGNgAtAAAAAA==.Sardenn:BAAANQADCgMIAwABNQAECggIHAARAOwUAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAAANQAECgUIEAAAAA==.',
Se='Seal:BAAANQADCggICQABNQAECgkJIgACAFEjAA==.Serge:BAAANQADCggICAABNQADCgYIDAADAAAAAA==.',
Sg='Sgtmoose:BAAANQAECgUICgAAAA==.',
Sh='Shabamzoo:BAAANQADCgEIAQAAAA==.Shadeswift:BAAANQADCgcIFgAAAA==.Shadowhart:BAAANQAECgUIBwABNQAECggIKAALAGUbAA==.Sharindlar:BAABNQAECoEiAAICAAkKnR71DQAsAwACAAkKnR71DQAsAwAAAA==.Sharpeye:BAAANQAECgEIAQAAAA==.Shokanu:BAABNQAECoEaAAIQAAgKfxsLBwCTAgAQAAgKfxsLBwCTAgAAAA==.Shrimpmeat:BAAANQADCgQIBgAAAA==.',
Si='Sib:BAAANQADCgcICQAAAA==.Silverlight:BAAANQAECgQICAABNQADCgYIDAADAAAAAA==.Sissyo:BAAANQAECgEIAQAAAA==.',
Sk='Skeets:BAAANQADCgcIEAAAAA==.Skeëts:BAAANQADCgIIAgAAAA==.Skêets:BAAANQADCgEIAQAAAA==.',
Sm='Smasshley:BAAANQADCgYIBgAAAA==.Smolgoblin:BAAANQADCgcIEAAAAA==.',
Sn='Snakie:BAAANQAECgIIBgAAAA==.',
So='Sokorag:BAABNQAECoEXAAIGAAgK1BbaLwAVAgAGAAgK1BbaLwAVAgAAAA==.Soulsnack:BAAANQAECgcIEAAAAA==.',
Sp='Specer:BAAANQAECggJBAAAAA==.Spedspidspud:BAABNQAECoEWAAITAAcK1BQzJQDgAQATAAcK1BQzJQDgAQAAAA==.Spoone:BAAANQADCgYIBgAAAA==.',
St='Starrbuck:BAAANQAECgUIEAAAAA==.Stolas:BAAANQADCgcIBwAAAA==.Stryke:BAAANQAECgIIAgAAAA==.',
Su='Sunfury:BAAANQADCggIEQAAAA==.Supergobbler:BAAANQADCgEIAQAAAA==.Suterareta:BAAANQAECgQICQAAAA==.',
Sy='Syl:BAAANQADCgEIAQAAAA==.Synderella:BAABNQAECoEgAAMWAAgKcBNVCQD3AQAWAAgKcBNVCQD3AQASAAIKoAU7aQBcAAAAAA==.',
['Sï']='Sïntaxerror:BAAANQAECgMIAwAAAA==.',
Ta='Taksun:BAAANQAECgUICgAAAA==.Tanaka:BAAANQAECgQIBwAAAA==.Tandy:BAABNQAECoEWAAILAAgKdx7DJADLAgALAAgKdx7DJADLAgAAAA==.Tauntindeath:BAABNQAECoEcAAIFAAgKoA7uRQCfAQAFAAgKoA7uRQCfAQAAAA==.Tav:BAABNQAECoEgAAMXAAgKECDIMQDHAgAXAAgKECDIMQDHAgAYAAEK+RpSLwBMAAAAAA==.',
Th='Thaladrin:BAAANQAECgIIAgAAAA==.Thalard:BAAANQAECgIIAwAAAA==.',
Ti='Tianara:BAAANQAECgMJAwAAAA==.Tidebloom:BAAANQAECgUIDAAAAA==.',
To='Toffeecocoa:BAAANQAECgIIAgAAAA==.Tokens:BAAANQAECgMIAwAAAA==.Toohottotrot:BAAANQADCgYICwAAAA==.Torrent:BAABNQAECoEiAAICAAkKUSM5CABkAwACAAkKUSM5CABkAwAAAA==.Toy:BAAANQADCgYJCQAAAA==.',
Tr='Trixxe:BAABNQAECoEZAAITAAgKEhSUHwAWAgATAAgKEhSUHwAWAgAAAA==.Trojaan:BAAANQAECggIAQAAAA==.Trostani:BAAANQABCgEIAQAAAA==.Trulisha:BAABNQAECoEqAAIZAAgKiBxEJgCwAgAZAAgKiBxEJgCwAgAAAA==.Trurala:BAAANQAECgMIBQAAAA==.',
Ty='Tyleinthrel:BAAANQADCgIIAgAAAA==.',
Uo='Uog:BAAANQADCgUIBQAAAA==.',
Ur='Ursalaisis:BAAANQADCgEIAQAAAA==.',
Va='Vacum:BAAANQAECgQIBAAAAA==.Vaderon:BAAANQAECgIIAgAAAA==.Vandremont:BAAANQADCgMIAwAAAA==.Vayine:BAAANQAECgQJBgAAAA==.',
Ve='Velk:BAAANQAECgYIBgAAAA==.Venmo:BAAANQADCgIIAgABNQAECgUIDwADAAAAAA==.',
Vi='Visenya:BAAANQADCgYIBgAAAA==.Vispiam:BAAANQADCgQIBAAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAFFAMIBQAZAG4VAA==.Voodòó:BAAANQADCgYIBgAAAA==.',
Vu='Vuskar:BAAANQAECgUIDQAAAA==.',
Wa='Warpaths:BAAANQAECgQICgABNQAECgcIDQADAAAAAA==.',
Wh='Whisperwilow:BAAANQABCgIJAgAAAA==.',
Wi='Wide:BAAANQAECggIDgAAAA==.Wigglyears:BAABNQAECoEcAAMaAAgKdBGeHwDxAQAaAAgKdBGeHwDxAQAbAAEKyQA2KAAeAAAAAA==.',
Wo='Wombat:BAAANQAECggIEQABNQAFFAEIAQADAAAAAA==.',
Wr='Wreckoning:BAAANQAECgMIAwAAAA==.',
Xa='Xanadaria:BAAANQAECgQICAAAAA==.Xanalhano:BAAANQADCgQIBAAAAA==.Xanalluna:BAAANQADCggIGAABNQAECgQICAADAAAAAA==.Xanvarani:BAAANQADCggICwABNQAECgQICAADAAAAAA==.',
Xe='Xeril:BAAANQABCgIIAgAAAA==.',
Ya='Yakushimaru:BAABNQAECoEaAAIKAAgKziALFQD3AgAKAAgKziALFQD3AgAAAA==.',
Yo='Yoonah:BAAANQADCgQICAAAAA==.',
Za='Zarella:BAAANQAECgUICwAAAA==.Zarifa:BAAANQAECgMIAwABNQAECgUICwADAAAAAA==.',
Ze='Zefren:BAABNQAECoEgAAIPAAcKvhsPXQArAgAPAAcKvhsPXQArAgAAAA==.Zev:BAAANQADCgYIDAAAAA==.',
Zi='Zildon:BAAANQADCgYIEAAAAA==.',
Zu='Zurik:BAACNQAFFIEJAAIQAAUKfBC8AACdAQAQAAUKfBC8AACdAQA1AAQKgR8AAhAACQpsIIwEAPcCABAACQpsIIwEAPcCAAAA.',
['Ør']='Ørìon:BAAANQADCgUIBQAAAA==.',
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
