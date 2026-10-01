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

local lookup = {'Paladin-Retribution','Mage-Arcane','Mage-Frost','Unknown-Unknown','Hunter-BeastMastery','Rogue-Assassination','DemonHunter-Havoc','Paladin-Holy','Priest-Holy','Shaman-Restoration','Shaman-Elemental','DeathKnight-Blood','Warlock-Demonology','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Warrior-Arms','Warrior-Fury','Rogue-Subtlety','Paladin-Protection','Warlock-Destruction','Shaman-Enhancement','Warrior-Protection','Druid-Restoration','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Achkmed:BAAANQADCggIEQAAAA==.',
Ad='Adelaid:BAAANQAECgEIAQABNQAFFAQIBgABAGYOAA==.',
Ae='Aethelle:BAAANQADCggICAAAAA==.',
Ak='Akalon:BAAANQAECgcIEQAAAA==.',
Al='Alexandrìte:BAAANQADCgcIEQAAAA==.Allfrost:BAAANQADCggIEQAAAA==.Aluda:BAAANQAECgUIDAAAAA==.',
An='Anùbis:BAAANQADCgIIAgAAAA==.',
Ao='Aoeina:BAABNQAECoEaAAMCAAgKGhfHfABMAgACAAgKJxXHfABMAgADAAEKJRjuLwBMAAAAAA==.',
Ap='Apollo:BAAANQAECgUIDgAAAA==.',
Ar='Arcanelotus:BAAANQADCgIIAwAAAA==.Ariaves:BAAANQAECgcIEQAAAA==.Arlind:BAAANQADCgcIEgAAAA==.Arthara:BAAANQABCgQIBQAAAA==.',
As='Astelana:BAAANQAECgUIDAAAAA==.',
At='Atanatari:BAAANQADCgcIEAABNQAECgYIDgAEAAAAAA==.Athennah:BAAANQADCgQIBAAAAA==.',
Ba='Bassotan:BAAANQAECgcIEwAAAA==.Baticus:BAAANQADCgcIBwAAAA==.',
Be='Beleva:BAAANQAECgIIBQAAAA==.',
Bj='Bjornagain:BAAANQADCggIEAAAAA==.Björne:BAAANQADCggIFAAAAA==.',
Bl='Blackendmoon:BAAANQAECgUICgAAAA==.Blackløtus:BAAANQAECggIEAAAAA==.Bloodedge:BAAANQAECgUICgAAAA==.Bloodklaat:BAAANQADCgYIBgAAAA==.Bloodnight:BAAANQAECgYIDwAAAA==.Bluebubbles:BAAANQADCggIIQAAAA==.Bluéyes:BAAANQAECgMIAwAAAA==.Blvckscvl:BAABNQAECoEZAAIFAAgKMR0xKQC3AgAFAAgKMR0xKQC3AgAAAA==.Blynna:BAAANQADCgYICQAAAA==.',
Br='Brannik:BAAANQAECgUIBwAAAA==.Breña:BAAANQADCggIGAAAAA==.Broadleaf:BAAANQAECgQICAAAAA==.',
Ca='Camiliana:BAAANQADCgUIBQAAAA==.',
Ce='Cellulight:BAAANQAECgUIDAAAAA==.',
Ch='Charizard:BAAANQAECgcIGAAAAQ==.Chelais:BAAANQAECgMIAwABNQABCgIJAgAEAAAAAA==.Cherrycola:BAAANQAECgQICAAAAA==.Chobits:BAAANQAECgQIBAAAAA==.',
Co='Coppertopp:BAAANQADCgQJBQAAAA==.Corvany:BAAANQAECgUICwAAAA==.',
Cr='Crawley:BAABNQAECoE5AAIGAAgKCxsjFACSAgAGAAgKCxsjFACSAgAAAA==.Crazalulla:BAAANQADCgcIBwAAAA==.Creeder:BAABNQAECoEdAAIBAAcKqQ6HlgCKAQABAAcKqQ6HlgCKAQAAAA==.',
Da='Dagoland:BAAANQADCggIBQAAAA==.Dainty:BAAANQADCggICgABNQAFFAUICQAFAPkOAA==.',
De='Deaanor:BAAANQAECgEJAQAAAA==.Deathcòw:BAAANQAECgYICwAAAA==.Deween:BAAANQAECgYIDAAAAA==.',
Di='Dionysuz:BAAANQAECgcICwAAAA==.',
Do='Dojoro:BAAANQAECgQIBwAAAA==.Dorc:BAAANQADCgMIAwAAAA==.Dotsarelocks:BAAANQADCggIDAAAAA==.',
Dr='Dradyos:BAAANQADCggIFQAAAA==.Draegare:BAAANQAFFAEIAQAAAA==.Drdeer:BAAANQADCgUIBgAAAA==.',
Ee='Eelecurb:BAAANQADCggIDwAAAA==.',
Ei='Eisysae:BAAANQABCgIJAwAAAA==.',
El='Eliard:BAAANQABCgYIBwAAAA==.',
Er='Erisynn:BAEANQADCgUIBQABNQAECgkJPgAHAJ0TAA==.',
Et='Eternalx:BAAANQADCgYJCgAAAA==.',
Ev='Evang:BAAANQAECgUICgAAAA==.Everd:BAAANQAECgYICwAAAA==.',
Fi='Fiametta:BAAANQAECgUIDwAAAA==.Firerain:BAAANQADCggJEQAAAA==.',
Fo='Forkingidiot:BAAANQAECgQIBAAAAA==.Forodin:BAAANQADCgYIBgABNQADCggIFAAEAAAAAA==.Foxymizzy:BAAANQAECgQIBAABNQAECggIGQAIAN8cAA==.',
Fr='Freadrick:BAAANQADCgEIAQABNQADCggIFAAEAAAAAA==.Frostknight:BAAANQADCggIDgAAAA==.',
Fu='Funsize:BAABNQAECoEcAAIJAAcKkh0oOgA6AgAJAAcKkh0oOgA6AgAAAA==.Furyfangd:BAAANQADCgYIBwAAAA==.',
Ga='Gazzlok:BAAANQADCggIDgAAAA==.',
Ge='Gesen:BAAANQADCggIFQAAAA==.',
Gl='Gloriance:BAAANQAECgUICgAAAA==.',
Go='Gondra:BAAANQABCgIIBAABNQAECgUICwAEAAAAAA==.Gortalon:BAAANQABCgIIAgAAAA==.',
Ha='Haplo:BAAANQADCggIEAAAAA==.',
He='Hellmet:BAAANQAECgIJAgAAAQ==.Hey:BAABNQAECoEhAAMKAAkKSyCqEgAIAwAKAAkKSyCqEgAIAwALAAQKOQe/uQDFAAAAAA==.',
Hi='Hinamori:BAAANQADCgYIBwAAAA==.',
Hu='Huogmi:BAAANQABCgIJBwAAAA==.',
Il='Ilharra:BAAANQAECgEIAQAAAA==.Ilililili:BAAANQADCgYICQAAAA==.Illee:BAAANQAECgQICgAAAA==.',
Im='Impgangpimp:BAEANQAECgYIDAABNQAECgYIDAAEAAAAAA==.Imturtle:BAABNQAECoEZAAIMAAcKeSL+GQCsAgAMAAcKeSL+GQCsAgABNQAECggIHQANANUSAA==.',
Ir='Irmis:BAAANQADCgcIGAABNQAECgQIBgAEAAAAAA==.',
Iu='Iupiter:BAAANQAECgIIAgAAAA==.',
Iy='Iyahlieairia:BAAANQAECgMIBAAAAA==.',
Iz='Izabeth:BAAANQAECgUICQAAAA==.',
Ja='Jamella:BAAANQAECgYIEQAAAA==.',
Je='Jesüschrist:BAAANQAECgEIAQAAAA==.',
Ju='Judeath:BAAANQABCggICQABNQADCggIGAAEAAAAAA==.',
Ka='Kabocha:BAAANQAECgcIDgAAAA==.Katsa:BAAANQADCgQIBgAAAA==.Kawi:BAAANQABCgIIAwAAAA==.',
Ki='Kiraneem:BAAANQAECgUIDwAAAA==.Kittie:BAABNQAECoEgAAIKAAgKghQYTADjAQAKAAgKghQYTADjAQAAAA==.',
Kr='Krinj:BAABNQAECoEdAAMOAAcKCR6vIgAkAgAOAAcKCR6vIgAkAgAPAAEKOQskrQA1AAAAAA==.Kristov:BAAANQADCggICAAAAA==.',
Kt='Ktariani:BAAANQADCgUJBQAAAA==.',
Ky='Kyarla:BAAANQAECgMIAwAAAA==.Kyden:BAAANQADCgEIAQAAAA==.',
La='Lazulie:BAAANQADCgcIBwAAAA==.',
Le='Leahim:BAABNQAECoE5AAIMAAgKHh5dGgCpAgAMAAgKHh5dGgCpAgAAAA==.Ledani:BAAANQAECgQIDgAAAA==.Leonato:BAAANQADCgEIAQAAAA==.',
Li='Lilbulky:BAAANQADCgQIBAABNQAECgcIEQAEAAAAAA==.',
Lo='Lohith:BAABNQAECoEdAAIKAAcKjAWKhwAgAQAKAAcKjAWKhwAgAQAAAA==.Lonedawg:BAAANQADCggIEAAAAA==.Lourival:BAAANQAECgQJBAAAAA==.Lovécoil:BAAANQAECgYICgAAAA==.',
Lu='Lunâ:BAAANQAECgYJEgAAAA==.',
['Lë']='Lëw:BAAANQAECgIIAwAAAA==.',
Ma='Marsyx:BAABNQAECoEdAAIJAAcK7xvaOgA3AgAJAAcK7xvaOgA3AgAAAA==.Matidan:BAAANQAECgUICgAAAA==.Mayael:BAABNQAECoEcAAMPAAgKjxhTPQDFAQAPAAcKVBlTPQDFAQAOAAcKeA6MNwCIAQAAAA==.',
Me='Medreaux:BAABNQAECoE9AAMJAAkKph7DEwACAwAJAAgKTiLDEwACAwAQAAEKdgA0eAACAAAAAA==.Merrei:BAAANQAECgcICgAAAA==.Meta:BAAANQADCggICAABNQAECgcIHQAMAGIXAA==.Metalknyte:BAAANQAECgUIDwAAAA==.',
Mi='Miniknyte:BAAANQAECgUIDwAAAA==.',
Mo='Mohu:BAAANQADCgcIBwAAAA==.Monkey:BAAANQADCgcICgAAAA==.Moonsz:BAAANQADCggIKAAAAA==.Mooseonloose:BAAANQAECggIAgAAAA==.Morandus:BAAANQAECgEIAQAAAA==.Moraria:BAAANQADCgMIAwAAAA==.Morgrathh:BAAANQADCgYIBgAAAA==.',
My='Mychelle:BAAANQAECgQIDwAAAA==.',
Na='Nakryn:BAAANQAECgUIDwAAAA==.Natorn:BAABNQAECoEdAAIRAAcKwSJEPgCXAgARAAcKwSJEPgCXAgAAAA==.Nay:BAAANQAECgcJCQAAAA==.',
Ne='Nemrod:BAAANQAECgEIAQAAAA==.Nezum:BAAANQADCgUIDwAAAA==.',
Ni='Nickoli:BAAANQADCggIEgAAAA==.Niterend:BAAANQAECgcIEQAAAA==.',
No='Norabel:BAAANQADCgQICAAAAA==.',
['Nø']='Nøxxi:BAAANQAECgUIDwAAAA==.',
Ob='Obbimcanood:BAAANQADCgIIAgAAAA==.',
Ok='Okbloomer:BAAANQAECgYICgABNQAFFAUICwAJAMsYAA==.',
Ol='Oldben:BAAANQAECgYIEgAAAA==.',
Or='Oriel:BAAANQAECgYIDwAAAA==.',
Ov='Ovy:BAAANQAECgEIAQAAAA==.',
Pa='Paleblueeye:BAAANQADCgIIAgAAAA==.',
Pi='Pixystix:BAAANQADCgYIDAABNQAECgQIDwAEAAAAAA==.',
Pl='Plop:BAAANQADCgUIBQABNQAECgQIBAAEAAAAAA==.Plumpcheeks:BAAANQADCggIDQAAAA==.',
Po='Poc:BAAANQAECgMIBgAAAA==.Poundya:BAAANQADCgQIBAAAAA==.',
Pr='Prinsana:BAAANQAECgUIDwAAAA==.',
Pu='Purquis:BAAANQAECgIIAgAAAA==.',
Re='Reaperlord:BAAANQAECgUIDAAAAA==.',
Ri='Rizzardofoz:BAAANQADCgMIAwAAAA==.',
Rl='Rllybuffnerd:BAAANQAECggICQAAAA==.',
Ro='Rodikus:BAAANQAECgcIEwAAAA==.',
Sa='Saiaa:BAAANQAECgUIDgAAAA==.Sakeena:BAAANQADCggIEAAAAA==.Samará:BAAANQADCgQICAAAAA==.Sarleigh:BAAANQADCgIIAgAAAA==.Sattia:BAAANQAECgUJDQAAAA==.',
Sh='Shenanygins:BAAANQADCgMIAwAAAA==.Shendalla:BAAANQABCgQIBAAAAA==.Shinokishi:BAAANQAECgUICAAAAA==.',
Si='Silentninjaa:BAABNQAECoEWAAISAAcK3wreDQCCAQASAAcK3wreDQCCAQAAAA==.Simphunter:BAEANQAECgYIDAAAAA==.Sinfel:BAAANQAECgQIBwAAAA==.Sit:BAAANQADCggICAAAAA==.',
Sk='Skoriko:BAABNQAECoEdAAMTAAcKDBsGEgBBAgATAAcKDBsGEgBBAgAGAAMK2gxFXgCdAAAAAA==.',
So='Sonett:BAAANQADCggIEAAAAA==.Sonto:BAAANQAECgIIAgAAAA==.',
Sp='Sparks:BAAANQADCgYIBgAAAA==.Splunk:BAABNQAECoEdAAIMAAcKYhceOADnAQAMAAcKYhceOADnAQAAAA==.',
St='Staggerdaddy:BAAANQAECgQIBgAAAA==.Stariya:BAAANQADCggIDAAAAA==.Stompinghoof:BAAANQAECgYICAAAAA==.Strawyà:BAAANQAECgYJDwAAAA==.',
Sy='Syannara:BAAANQADCggIJAAAAA==.Syssa:BAAANQAECgIIBQABNQAECgIIAgAEAAAAAA==.',
['Sì']='Sìrocco:BAAANQAECgQIBgAAAA==.',
Ta='Taleranor:BAAANQADCggIFwAAAA==.Tamerizer:BAAANQAECgcIEgAAAA==.',
Te='Tearali:BAAANQADCgEIAQAAAA==.Teejrath:BAAANQAECgcICwAAAA==.Teekeez:BAAANQADCggICQAAAA==.',
Th='Thekal:BAAANQADCgEIAgAAAA==.Theodorel:BAAANQAECgEIAQAAAA==.Thicchick:BAAANQAECgQIBgAAAA==.Thirge:BAAANQAECgQIBwAAAA==.Thorek:BAAANQADCgcIBwAAAA==.Thundertaco:BAAANQAECgQIBwAAAA==.',
Ti='Tighten:BAAANQABCgEIAQAAAA==.',
To='Tofaaway:BAAANQADCggIEAAAAA==.Tolak:BAAANQAECgQIBwAAAA==.Tormikinos:BAAANQAECgUICgAAAA==.Torturousôwl:BAAANQAECgUICgAAAA==.Totemknyte:BAAANQABCgUIBQABNQAECgUIDwAEAAAAAA==.',
Tr='Trillianh:BAAANQADCgEIAQAAAA==.Trisky:BAABNQAECoEfAAMIAAcKvh2JNQBSAgAIAAcKvh2JNQBSAgAUAAEKMw/FWQAtAAAAAA==.',
Tu='Turtle:BAABNQAECoEdAAMNAAgK1RIObQC/AQANAAcK9RAObQC/AQAVAAIKvRAGTQCCAAAAAA==.',
Un='Unholyghost:BAAANQABCgUICgAAAA==.',
Va='Vadrakquin:BAAANQAECgcIDgAAAA==.Valshamommy:BAABNQAECoEVAAIWAAcKrw3hEwDUAQAWAAcKrw3hEwDUAQAAAA==.Vanloth:BAAANQADCgEIAQAAAA==.Vantadim:BAAANQADCgMIAwAAAA==.',
Ve='Vegito:BAAANQAECgIIBQAAAA==.',
Vi='Viverrid:BAAANQAECgEIAQAAAA==.',
Vo='Voin:BAABNQAECoEjAAIXAAkKayQZAQCwAwAXAAkKayQZAQCwAwAAAA==.Vorpine:BAAANQAECgcIEwAAAA==.',
We='Wetkittie:BAAANQADCgYIBwAAAA==.',
Wi='Wiccawitch:BAAANQADCgYIEgAAAA==.Wirhl:BAAANQAECgIIBgAAAA==.',
Wo='Worthatry:BAABNQAECoEdAAIBAAgKVyELLgDTAgABAAgKVyELLgDTAgAAAA==.',
Xa='Xalbit:BAAANQAECgUIDgAAAA==.Xantia:BAABNQAECoEcAAIYAAgKhQwGJQCYAQAYAAgKhQwGJQCYAQAAAA==.',
Xe='Xenlo:BAAANQAECgYICAAAAA==.',
Yo='Yogurt:BAAANQADCgMJAwABNQAECgIJAgAEAAAAAA==.',
Za='Zaizel:BAAANQAECgEIAQABNQAFFAUICAAZAE4PAA==.Zalulu:BAAANQAECgMIAwAAAA==.Zathennyx:BAAANQAECgMIAwAAAA==.',
Ze='Zenpai:BAAANQAECgQJBgAAAA==.',
Zv='Zvorunalotus:BAAANQADCgYIDQAAAA==.',
['Ðr']='Ðread:BAAANQAECgMIAwAAAA==.',
['ßß']='ßßqñüt:BAAANQAECgUIDwAAAA==.',
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
