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

local lookup = {'Unknown-Unknown','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Mage-Arcane','Paladin-Holy','Mage-Fire','Mage-Frost','Druid-Balance','Hunter-BeastMastery','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Paladin-Retribution','Druid-Feral','Hunter-Survival','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Warrior-Arms','Warrior-Protection','Shaman-Elemental',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-09-22',data={Ae='Aelita:BAAANQAECgQJCAAAAA==.',
Af='Afflicted:BAAANQAECgUJCQABNQAECgcIBwABAAAAAA==.',
Ag='Agarne:BAAANQAECgQIBQAAAA==.',
Ai='Aimster:BAAANQADCgQIBAAAAA==.',
Ak='Akhta:BAAANQAECgYJDwAAAA==.',
Al='Allaris:BAAANQAECgQJBwAAAA==.Allíesin:BAAANQADCgcIEAAAAA==.Altryn:BAAANQABCgQIBAAAAA==.Alundrablaze:BAAANQAECgYIEwAAAA==.',
Am='Amarixa:BAAANQADCgQIBgABNQAECgQIBAABAAAAAA==.Amzng:BAAANQABCggJDQAAAA==.',
An='Anoint:BAAANQADCgQIBAABNQAECgkJKAACALciAA==.Anrraakk:BAAANQADCgYIBgAAAA==.Antonello:BAAANQADCgcIBwAAAA==.',
Ar='Aranthino:BAAANQAECgUJCwAAAA==.Arnzul:BAAANQAECgQJBgAAAA==.Aryabhatta:BAAANQAECgUJCgAAAA==.',
As='Asakura:BAABNQAECoEWAAIDAAgKjBgZJQAuAgADAAgKjBgZJQAuAgAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.',
Ba='Ballrogg:BAAANQADCgIJAgAAAA==.Bamdk:BAABNQAECoEaAAMEAAgKdxtvJQA4AgAEAAgKMRZvJQA4AgADAAcKeRLZPACcAQAAAA==.Bamshambam:BAAANQAECgUIDAABNQAECggJGgAEAHcbAA==.Baoshengdadi:BAAANQADCgMIAwABNQAECgkJGQAFAJQdAA==.',
Be='Beansfu:BAAANQAECgYIDAABNQAECgcIEAABAAAAAA==.Beansinator:BAAANQAECgcIEAAAAA==.Beefsupriem:BAAANQAECgUJCwAAAA==.Bellatrïx:BAAANQADCgcJFQABNQADCgcIEAABAAAAAA==.Belliaz:BAAANQAECgQIBAAAAA==.',
Bg='Bgwinnier:BAAANQADCgYIBgAAAA==.',
Bi='Bialar:BAAANQADCgYIDAAAAA==.Bigchéésé:BAAANQAECgQIBAAAAA==.Biteme:BAAANQABCgIJAgAAAA==.',
Bl='Blackforge:BAAANQABCgMIAwAAAA==.Bloodwell:BAAANQAECgUJCQAAAA==.',
Bo='Bovinar:BAAANQAECgIJAwAAAA==.',
Br='Bruzera:BAAANQAECgUJBQAAAA==.',
Bu='Bulldan:BAAANQAECgUJCgAAAA==.Buzrkk:BAAANQAECgUIBQAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
Ca='Candyquartz:BAAANQAECgEIAQAAAA==.Captaïn:BAAANQAECgIIAgAAAA==.',
Ce='Celladorne:BAAANQADCggIEAAAAA==.',
Cg='Cg:BAABNQAECoEYAAIGAAgKdBpHWACEAgAGAAgKdBpHWACEAgAAAA==.',
Ch='Chibi:BAAANQAECgEIAgAAAA==.Chrent:BAAANQAECgIIAgAAAA==.Chronokite:BAAANQAECgQIBgAAAA==.',
Cl='Clawburr:BAAANQADCgQIBwABNQAECgEIAQABAAAAAA==.Clelronah:BAAANQADCgYIBwAAAA==.',
Cy='Cybele:BAAANQADCggIBgABNQAECgQIBgABAAAAAA==.',
Da='Dalmaar:BAAANQABCgEIAQAAAA==.Dantae:BAAANQADCgYICQAAAA==.Darafragen:BAABNQAECoEWAAIHAAgKWRb4MAA6AgAHAAgKWRb4MAA6AgAAAA==.',
De='Deader:BAAANQAECgMJAwAAAA==.Demonseed:BAAANQADCgYJBgAAAA==.Demonslice:BAAANQADCggJGQAAAA==.Dentarus:BAAANQADCggICAAAAA==.',
Di='Disengage:BAAANQAECgEIAQAAAA==.Displace:BAAANQAECgEIAQAAAA==.Divinewords:BAAANQAECgYICAAAAA==.Divish:BAAANQAECgUIBwAAAA==.',
Dk='Dkramm:BAAANQAECgYIBwAAAA==.',
Do='Donhector:BAAANQAECgYJEwAAAA==.Dontsheep:BAAANQAECgUICQAAAA==.Doubl:BAAANQAECgEIAgAAAA==.',
Dr='Dracowarrior:BAAANQADCgQJBAAAAA==.Drak:BAAANQADCgYIBgAAAA==.Dreyvia:BAAANQADCgQIBAAAAA==.Druecc:BAAANQAECgQJCgAAAA==.Druidlord:BAAANQAECgQIBQAAAA==.Druidpeng:BAAANQADCgUIBQAAAA==.',
Du='Dundalo:BAAANQADCgYIBgAAAA==.',
['Då']='Dågon:BAAANQAECgEIAQAAAA==.',
El='Elchaman:BAAANQADCgcIDAAAAA==.Elcuh:BAAANQADCggIDgAAAA==.Ellennia:BAAANQADCgUIBQAAAA==.Ellisandré:BAABNQAECoEhAAQGAAkKdh1yNADwAgAGAAkK9htyNADwAgAIAAEKnhMAAAAAAAAJAAMKGiAAAAAAAAAAAA==.',
Er='Era:BAAANQADCggJHQAAAA==.',
Ev='Evilinside:BAAANQADCgYIBgAAAA==.',
Fa='Fanara:BAAANQADCgUJBQAAAA==.Farty:BAAANQAECgIJBAAAAA==.',
Fi='Fianchetto:BAAANQABCgIIAgAAAA==.Fitua:BAAANQADCggICAAAAA==.',
Fo='Fortytwö:BAAANQAECgQIBQAAAA==.Foutre:BAAANQAECgUJBwAAAA==.',
Fr='Fruntstabba:BAAANQAECgEIAQAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBQAAAA==.Fungus:BAABNQAECoEhAAMKAAkK6iRCAwC0AwAKAAkK6iRCAwC0AwACAAEKOiV9KABsAAAAAA==.Fuzzytotems:BAAANQADCgcJEAAAAA==.',
Fy='Fynnick:BAAANQAECgQIBAAAAA==.',
Ga='Gaar:BAAANQAECgEIAQAAAA==.Galgar:BAAANQAECgQIBgAAAA==.',
Ge='Getlnmyvan:BAAANQAECgYJCwAAAA==.',
Gh='Ghoulgranny:BAAANQADCgcICgAAAA==.',
Gl='Glert:BAAANQAECgEIAQAAAA==.',
Go='Goinmonk:BAAANQADCgYICgAAAA==.Goinsolo:BAABNQAECoEaAAILAAgK/gsIUgD7AQALAAgK/gsIUgD7AQAAAA==.Gorvax:BAAANQAECgUJCwAAAA==.Gozz:BAAANQABCgQIBQAAAA==.',
Gr='Grimlóck:BAAANQAECgIJBAAAAA==.Grumok:BAAANQABCgQIBQAAAA==.',
Gw='Gwenledyr:BAABNQAECoEXAAQMAAgKLRGbCgBBAQAMAAUKVhCbCgBBAQANAAMK2g1aOgC0AAAOAAMKNg/XtwCzAAAAAA==.Gwynhria:BAAANQAECgQIBAAAAA==.',
Ha='Hallebearie:BAAANQAECgQJBAABNQADCgIIAgABAAAAAA==.',
He='Heathèn:BAAANQAECgEIAQAAAA==.Heimthrall:BAAANQAECgUIBQAAAA==.Hekus:BAEBNQAECoEaAAIPAAcKYRqJSwAmAgAPAAcKYRqJSwAmAgAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Horohöro:BAABNQAECoEoAAICAAkKtyJPAQCRAwACAAkKtyJPAQCRAwAAAA==.',
Hu='Hugme:BAAANQADCgYIBgABNQAECgUJCwABAAAAAA==.Hukari:BAAANQADCgQIBAABNQAECgkJHgAQAGwgAA==.',
['Hà']='Hàwk:BAAANQABCgIJAwAAAA==.',
Ic='Icelynn:BAAANQAECggIDQABNQAECgkJIgALAGkgAA==.',
Ii='Iiambloody:BAAANQADCgQIBAAAAA==.Iil:BAAANQADCggJFAAAAA==.',
Iq='Iqsamurai:BAAANQABCgYIBgAAAA==.',
It='Itruszia:BAAANQAECgQIBAAAAA==.',
Ja='Jaxxia:BAAANQAECgEJAQABNQAECgUIDAABAAAAAA==.',
Jb='Jblaze:BAAANQAECgUIBQAAAA==.',
Jh='Jhalicistu:BAAANQAECgIIAgAAAA==.',
Ju='Juzomido:BAABNQAECoEcAAIRAAgKUCFtAgCrAgARAAgKUCFtAgCrAgAAAA==.',
Ka='Kaijhin:BAAANQAECgUIDAAAAA==.Kaline:BAAANQAECgIIAgAAAA==.Katianna:BAABNQAECoEXAAIFAAgKLBv5JgBrAgAFAAgKLBv5JgBrAgAAAA==.',
Ke='Keallach:BAAANQAECgUIDAAAAA==.Kelanath:BAAANQAECgUICgAAAA==.',
Kh='Khalli:BAAANQAECgUJDAAAAA==.Khaps:BAAANQADCgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.Khora:BAAANQADCgYIBgAAAA==.',
Ki='Kiffprime:BAAANQADCgYICgAAAA==.Kittycatlj:BAAANQADCggIEQAAAA==.Kiyosara:BAAANQADCgYJCgAAAA==.',
Kr='Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQADCggIDAAAAA==.',
Ku='Kulrig:BAAANQADCgYIDAAAAA==.Kurri:BAAANQADCgYIFgAAAA==.',
La='Larde:BAAANQADCgcJEAABNQADCgYIDAABAAAAAA==.',
Li='Lightjohn:BAAANQADCgEJAQABNQADCggIEQABAAAAAA==.',
Lo='Loakal:BAAANQADCgQIBAAAAA==.Lovemarauder:BAAANQADCgYJBgAAAA==.',
Lu='Lunaari:BAAANQAECgQICgAAAA==.Lurarind:BAAANQAECgYIDAAAAA==.',
['Lè']='Lègendary:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.',
Ma='Maeday:BAAANQADCgQJBAAAAA==.Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAAANQAECgYICQAAAA==.Malganon:BAAANQAECgQIBQAAAA==.Malygoz:BAAANQAECgEIAQABNQAECgkJJwAPACchAA==.Martheiran:BAAANQAECgYJDQAAAA==.Mashpewtater:BAAANQAECgEIAQAAAA==.Mashpwntato:BAAANQABCgQIBgAAAA==.Mathelmana:BAAANQAECgUJCwABNQAECgYIEwABAAAAAA==.Mawika:BAAANQADCggJEgAAAA==.',
Mc='Mcbdeath:BAAANQADCggICAABNQAECgIIBAABAAAAAA==.',
Me='Mechafour:BAAANQAECgQIBQAAAA==.Medusaa:BAAANQAECgEIAQAAAA==.',
Mi='Miliandra:BAAANQADCgUIAQAAAA==.Minervasande:BAAANQADCgMIAwAAAA==.Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAABNQAECoEeAAISAAgKnha9HAA7AgASAAgKnha9HAA7AgAAAA==.Missfrost:BAAANQADCgMIAwAAAA==.Mistickay:BAAANQAECgIIAgAAAA==.Mizbeheaven:BAAANQADCgMJAwABNQAECgQIBAABAAAAAA==.',
Mo='Moreblood:BAAANQAECgUIDAAAAA==.Morghella:BAAANQAECgYJDwAAAA==.Morhsa:BAAANQABCgMIAwAAAA==.Moána:BAAANQADCgMIAwAAAA==.',
Mu='Murtaugh:BAAANQABCgQIBAAAAA==.',
Mw='Mw:BAAANQAECgQICAAAAA==.',
My='Mynadshealu:BAAANQADCgEIAQAAAA==.Mysticbrew:BAAANQAECgUICgAAAA==.Mythros:BAAANQAECgEIAQAAAA==.',
Ne='Nezalan:BAAANQADCgUIBQABNQAECgcJGQAJAIYcAA==.',
Ni='Nightwitch:BAAANQADCgYIBgAAAA==.',
No='Noirra:BAABNQAECoEeAAILAAgK8RnWLgB4AgALAAgK8RnWLgB4AgAAAA==.Noxxival:BAAANQADCgUIBQAAAA==.',
Om='Omusa:BAAANQAECgQIBAAAAA==.',
Or='Orcnick:BAAANQADCgcIEQAAAA==.',
Ov='Overfrosty:BAAANQAECgUJCwAAAA==.Overhealin:BAAANQADCgIIAgAAAA==.',
Oz='Ozaí:BAAANQADCgMIBAAAAA==.',
Pe='Peng:BAAANQAECgEIAQAAAA==.Pesto:BAAANQAECgMIBQAAAA==.',
Pi='Pinenuts:BAAANQABCgQIBgAAAA==.',
Ps='Psyberollin:BAAANQADCggICAAAAA==.',
Pu='Purgedfire:BAAANQADCgUICQAAAA==.',
Ra='Ratings:BAAANQADCgUIBQAAAA==.Rayda:BAAANQAECgIJBAAAAA==.',
Re='Reighan:BAAANQADCggIFAAAAA==.Renka:BAAANQAECgQIBwAAAA==.Revolting:BAABNQAECoEZAAITAAkK5h3tCgACAwATAAkK5h3tCgACAwAAAA==.',
Ri='Rianne:BAAANQAECgIJBQAAAA==.',
Ro='Rowanbow:BAAANQADCggIFgAAAA==.',
['Ré']='Rédd:BAAANQAECgMIAwAAAA==.',
Sa='Saberhawk:BAAANQAECgEJAQAAAA==.Sakurazuka:BAAANQAECgQICQAAAA==.Sanath:BAAANQAECgYIDwAAAA==.Sardenn:BAAANQADCgMIAwABNQAECgYJEAABAAAAAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAAANQAECgUJCwAAAA==.',
Se='Seal:BAAANQADCggICQABNQAECgkJHgAFAFEjAA==.Serge:BAAANQADCggICAABNQADCgYIDAABAAAAAA==.',
Sg='Sgtmoose:BAAANQAECgQJBQAAAA==.',
Sh='Shabamzoo:BAAANQADCgEIAQAAAA==.Shadeswift:BAAANQADCgYIDwAAAA==.Shadowhart:BAAANQAECgQJBgABNQAECggJHgALAPEZAA==.Sharindlar:BAABNQAECoEZAAIFAAkKlB3qCgA2AwAFAAkKlB3qCgA2AwAAAA==.Shokanu:BAAANQAECgYIEAAAAA==.Shrimpmeat:BAAANQADCgIIAwAAAA==.',
Si='Sib:BAAANQADCgcICAAAAA==.Silverlight:BAAANQAECgQICAABNQADCgYIDAABAAAAAA==.Sissyo:BAAANQAECgEIAQAAAA==.',
Sk='Skeets:BAAANQADCgcIDgAAAA==.',
Sm='Smasshley:BAAANQADCgYJBgAAAA==.Smolgoblin:BAAANQADCgYIDgAAAA==.',
Sn='Snakie:BAAANQAECgIIBAAAAA==.',
So='Sokorag:BAAANQAECgcIDQAAAA==.Soulsnack:BAAANQAECgUJCQAAAA==.',
Sp='Specer:BAAANQAECggJBAAAAA==.Spedspidspud:BAAANQAECgYIDgAAAA==.Spoone:BAAANQADCgYIBgAAAA==.',
St='Starrbuck:BAAANQAECgUJCwAAAA==.Stolas:BAAANQADCgcIBwAAAA==.Stryke:BAAANQADCggJHQAAAA==.',
Su='Sunfury:BAAANQADCggIEAAAAA==.Suterareta:BAAANQAECgQIBQAAAA==.',
Sy='Synderella:BAABNQAECoEZAAIUAAgKTRDwCADBAQAUAAgKTRDwCADBAQAAAA==.',
['Sï']='Sïntaxerror:BAAANQAECgMIAwAAAA==.',
Ta='Taksun:BAAANQAECgQIBQAAAA==.Tanaka:BAAANQAECgQIBAAAAA==.Tandy:BAAANQAECgcIEgAAAA==.Tauntindeath:BAAANQAECgYJEAAAAA==.Tav:BAABNQAECoEYAAMVAAgKtx7lLQCzAgAVAAgKtx7lLQCzAgAWAAEK+RqbJwBPAAAAAA==.',
Th='Thaladrin:BAAANQADCggJHQAAAA==.Thalard:BAAANQAECgIIAgAAAA==.',
Ti='Tianara:BAAANQAECgMJAwAAAA==.Tidebloom:BAAANQAECgQIBwAAAA==.',
To='Tokens:BAAANQAECgMIAwAAAA==.Toohottotrot:BAAANQADCgYICwAAAA==.Torrent:BAABNQAECoEeAAIFAAkKUSNbBQB6AwAFAAkKUSNbBQB6AwAAAA==.Toy:BAAANQADCgYJCQAAAA==.',
Tr='Trixxe:BAABNQAECoEZAAITAAgKEhRJGgA1AgATAAgKEhRJGgA1AgAAAA==.Trostani:BAAANQABCgEIAQAAAA==.Trulisha:BAABNQAECoEkAAIXAAgK9RYFPQAFAgAXAAgK9RYFPQAFAgAAAA==.Trurala:BAAANQAECgMIBQAAAA==.',
Ty='Tyleinthrel:BAAANQADCgIIAgAAAA==.',
Uo='Uog:BAAANQADCgUIBQAAAA==.',
Ur='Ursalaisis:BAAANQADCgEJAQAAAA==.',
Va='Vacum:BAAANQADCgYICgAAAA==.Vaderon:BAAANQADCgMIBQAAAA==.Vandremont:BAAANQADCgMIAwAAAA==.Vayine:BAAANQAECgQJBgAAAA==.',
Ve='Velk:BAAANQAECgYIBgAAAA==.Venmo:BAAANQADCgIIAgABNQAECgUJCwABAAAAAA==.',
Vi='Visenya:BAAANQADCgYIBgAAAA==.Vispiam:BAAANQADCgQIBAAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAECgkJGwAFAA0cAA==.Voodòó:BAAANQADCgYJBgAAAA==.',
Vu='Vuskar:BAAANQAECgQICAAAAA==.',
Wa='Warpaths:BAAANQAECgMIBgAAAA==.',
Wh='Whisperwilow:BAAANQABCgIJAgAAAA==.',
Wi='Wide:BAAANQAECggICAAAAA==.Wigglyears:BAAANQAECgYJEAAAAA==.',
Wo='Wombat:BAAANQAECggIDAAAAA==.',
Wr='Wreckoning:BAAANQAECgEIAQAAAA==.',
Xa='Xanadaria:BAAANQAECgQIBAAAAA==.Xanalhano:BAAANQADCgQIBAAAAA==.Xanalluna:BAAANQADCggIEgABNQAECgQIBAABAAAAAA==.Xanvarani:BAAANQADCggICwABNQAECgQIBAABAAAAAA==.',
Ya='Yakushimaru:BAAANQAECgYJDwAAAA==.',
Yo='Yoonah:BAAANQADCgQICAAAAA==.',
Za='Zarella:BAAANQAECgUIBQAAAA==.',
Ze='Zefren:BAABNQAECoEZAAIPAAcKwRoiSwAnAgAPAAcKwRoiSwAnAgAAAA==.Zev:BAAANQADCgYIBgAAAA==.',
Zi='Zildon:BAAANQADCgYIEAAAAA==.',
Zu='Zurik:BAABNQAECoEeAAIQAAkKbCAxAwAPAwAQAAkKbCAxAwAPAwAAAA==.',
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
