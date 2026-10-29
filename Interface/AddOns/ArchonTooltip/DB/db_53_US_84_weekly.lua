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

local lookup = {'DeathKnight-Blood','Shaman-Restoration','Hunter-BeastMastery','Warlock-Demonology','Mage-Arcane','Warlock-Destruction','Warrior-Protection','Warrior-Fury','Paladin-Protection','Monk-Windwalker','Warrior-Arms','Rogue-Subtlety','Paladin-Holy','DemonHunter-Vengeance','Druid-Balance','Druid-Restoration','Unknown-Unknown','Druid-Guardian','Mage-Frost','DeathKnight-Frost','Evoker-Devastation','Priest-Holy','Evoker-Augmentation','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Havoc','Paladin-Retribution','Rogue-Assassination','Priest-Shadow','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Shaman-Elemental','DeathKnight-Unholy','Monk-Brewmaster',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aardz:BAAANQADCggICAAAAA==.',
Ab='Abeblinkin:BAAANQADCgYICQAAAA==.Abraxîs:BAAANQAECgYICAAAAA==.',
Ac='Acindis:BAABNQAECn83AAIBAAoKcRJJOwAYAgABAAoKcRJJOwAYAgAAAA==.',
Ae='Aeless:BAAANQAECgQIBwAAAA==.Aelless:BAAANQADCgEIAQAAAA==.',
Ah='Ahzure:BAAANQAECggIEwABNQAECgkJKAACANsaAA==.',
Ai='Aithinne:BAAANQADCgUICQAAAA==.',
Al='Alch:BAAANQADCgQICAAAAA==.Aleandi:BAAANQADCgUIBQAAAA==.Aledil:BAAANQAECgYIDgAAAA==.Alynara:BAABNQAECn8wAAIDAAoKyBdzUgB5AgADAAoKyBdzUgB5AgAAAA==.',
Am='Amalthea:BAABNQAECn8WAAIEAAkK/AVgtQBkAQAEAAkK/AVgtQBkAQAAAA==.Amoredis:BAAANQABCggIFQAAAA==.',
An='Anume:BAAANQADCgYIDgAAAA==.Anwas:BAAANQAECgEIBAAAAA==.',
Ap='Apally:BAAANQADCgUIBQAAAA==.',
Ar='Aragan:BAAANQADCgQIBAAAAA==.Arellean:BAAANQADCgQIBAAAAA==.Arese:BAABNQAECn8YAAIFAAgKah5xUAC9AQAFAAgKah5xUAC9AQAAAA==.',
As='Asmodea:BAAANQAECgEIAQAAAA==.Asphonix:BAAANQAECgEIAgAAAA==.',
Az='Azzif:BAABNQAECn8XAAMGAAgK3wSREgCFAAAGAAcKbwWREgCFAAAEAAgKXAHLKgFoAAAAAA==.',
Ba='Babybluz:BAAANQAECgQIDAAAAA==.Baifeng:BAAANQABCggIFQAAAA==.Bandayde:BAAANQADCgYIBQAAAA==.Barlas:BAAANQAECgUIBQAAAA==.',
Be='Beauriley:BAABNQAECn8xAAMHAAoK1QpMHAB4AQAHAAoK1QpMHAB4AQAIAAEKdAYlJQAnAAAAAA==.Behomethan:BAAANQAECggIEgAAAA==.Belorc:BAAANQADCgIIAgAAAA==.Berian:BAAANQAECgIIAwAAAA==.',
Bi='Bigpapafreez:BAAANQADCggIDQABNQAECgoKRQAJABIcAA==.Billbetaray:BAAANQAECggIEwAAAA==.',
Bl='Blux:BAAANQADCgEIAQAAAA==.Bløødsong:BAAANQADCgEIAQAAAA==.',
Bo='Bombchele:BAABNQAECn8mAAIKAAgKZx4LDAA0AgAKAAgKZx4LDAA0AgAAAA==.Bowogibrann:BAAANQADCgQIBAAAAA==.',
Br='Bratticusrex:BAABNQAECn8oAAIIAAgK+gf2FwAgAQAIAAgK+gf2FwAgAQAAAA==.Brazier:BAAANQADCggICAAAAA==.Bresowar:BAAANQADCgIIAgAAAA==.Brynthe:BAAANQADCgYIDwAAAA==.',
Bu='Bunnylicious:BAABNQAECn8zAAICAAkKhSXTBgBcAwACAAkKhSXTBgBcAwAAAA==.Bunnymedic:BAAANQAECgMIAwABNQAECgkJMwACAIUlAA==.',
Ca='Caebrylla:BAABNQAECn8hAAIDAAgKgBTLXwB/AQADAAgKgBTLXwB/AQAAAA==.Cajun:BAABNQAECn8iAAILAAkKVhavRQC4AQALAAkKVhavRQC4AQABNQAFFAUIHAAMABkaAA==.Calistie:BAAANQADCggICAAAAA==.Callipygea:BAAANQADCgIIAgAAAA==.Camil:BAAANQADCgMIAwABNQAECgoKMAADAPENAA==.Cang:BAAANQABCggIIAAAAA==.Catalina:BAABNQAECn85AAINAAoK+R5rFgAkAwANAAoK+R5rFgAkAwAAAA==.',
Ce='Cecimorte:BAABNQAECn8jAAIBAAgKOxOHLgA1AQABAAgKOxOHLgA1AQAAAA==.',
Ch='Chargeasap:BAAANQADCgUIBQAAAA==.Charttopper:BAAANQAECgQIBQABNQAECgoKGwANAKwSAA==.Chinashop:BAAANQAECgQIBAABNQAECggIFgAOAOMgAA==.Chonker:BAABNQAECn86AAMPAAoK2RLPPAAQAgAPAAkKsRHPPAAQAgAQAAgK6xSDIgBIAQAAAA==.Chuckforrest:BAAANQADCgIIAgABNQAECgYIBgARAAAAAA==.',
Ci='Cihato:BAABNQAECn82AAISAAoKdxjiFAAZAgASAAoKdxjiFAAZAgAAAA==.',
Cl='Claye:BAAANQAECgIIAgAAAA==.Cleveistic:BAAANQADCgUIBwABNQAECgMIBgARAAAAAA==.Cleveland:BAAANQAECgMIBgAAAA==.',
Co='Coldshoulder:BAABNQAECn8gAAMFAAcKaRNKowAAAQAFAAYK8BJKowAAAQATAAIK7BPvLgCHAAAAAA==.Corelas:BAAANQAECgMIBgAAAA==.Couchdad:BAAANQAECgMICQABNQAECgcIDAARAAAAAA==.',
Cr='Crazymadman:BAAANQADCggIIQAAAA==.Crysallis:BAAANQADCggIHgAAAA==.',
Cy='Cynide:BAAANQADCgYJBgAAAA==.Cyyrene:BAAANQAECgEIAQABNQAECgoKGAAUAK8OAA==.',
Da='Dall:BAAANQAECgIIAwAAAA==.Damo:BAAANQAECgcICgAAAA==.Danale:BAAANQADCgYJCgAAAA==.Danknugz:BAAANQAECgYIEwAAAA==.Darwina:BAAANQAECgEIBQAAAA==.Dawnson:BAABNQAECn8YAAINAAgKGxmfMgDXAQANAAgKGxmfMgDXAQAAAA==.',
De='Deadscream:BAAANQAECggICwAAAA==.Deathlich:BAABNQAECn8UAAIUAAkKlxVsOwDhAQAUAAkKlxVsOwDhAQAAAA==.Demogless:BAAANQAECgQIBwAAAA==.Desyrel:BAAANQAECgIIAwABNQAECgYIFAAFAM0CAA==.',
Dh='Dharknight:BAAANQAECgQIBgABNQAECgUICAARAAAAAA==.Dharkuul:BAAANQAECgEIAQABNQAECgUICAARAAAAAA==.',
Di='Didimissfire:BAEBNQAECn81AAIDAAoKowpBRQDPAQADAAoKowpBRQDPAQAAAA==.Diefatty:BAAANQADCgMIAwAAAA==.',
Do='Doll:BAAANQADCgQIBAAAAA==.',
Dr='Draeven:BAAANQAECgUIBgAAAA==.Dranalis:BAAANQAECgEIBAAAAA==.Dredlok:BAAANQADCgYIEAAAAA==.',
Du='Dumonster:BAAANQAECgQIDwAAAA==.Dustdevil:BAAANQAECgYIBwABNQAECggIFgAOAOMgAA==.',
Ea='Eamishal:BAAANQAECgEIAQABNQAECgIIAgARAAAAAA==.',
Ee='Eeaassyy:BAAANQADCgYICQAAAA==.',
El='Elaraa:BAAANQADCgQIBAAAAA==.Eldorath:BAAANQAECgIIAgAAAA==.Elev:BAAANQADCgMIAwAAAA==.Elizabeth:BAAANQADCgUIBQAAAA==.',
Er='Eris:BAAANQADCggICAAAAA==.Erzascar:BAAANQAECgEIAQAAAA==.',
Es='Estrogen:BAABNQAECn8sAAIVAAoKfCJ+AwBvAwAVAAoKfCJ+AwBvAwAAAA==.',
Ev='Eventhorizon:BAAANQAECgYIAgAAAA==.Evolett:BAAANQAECgEIBQAAAA==.',
Fa='Fatbox:BAABNQAECn8zAAMIAAkKgh8CBQDcAgAIAAkKgh8CBQDcAgALAAEKrA0uVAEyAAAAAA==.Fayth:BAABNQAECn8vAAIWAAoKHB1qMgCeAgAWAAoKHB1qMgCeAgAAAA==.',
Fe='Fearkin:BAABNQAECn8nAAIXAAkKrAz+CwCbAQAXAAkKrAz+CwCbAQAAAA==.Fenastic:BAABNQAECn8nAAMEAAcKpAftuwBVAQAEAAcKpAftuwBVAQAYAAEKtwd2MAA0AAAAAA==.Fermy:BAAANQAECgIIBAAAAA==.Feyrah:BAAANQAECgEIAQAAAA==.',
Fi='Finraziel:BAAANQAECgEIAQAAAA==.Fiobhe:BAAANQAECgMIBgAAAA==.Fixeruper:BAAANQAECggIDwAAAA==.',
Fo='Fonz:BAAANQADCgYIBgABNQAECgYIEAARAAAAAA==.',
['Fí']='Físter:BAAANQADCgMIAwABNQAECgoKLAAZAHccAA==.',
Ga='Gazember:BAAANQAECgEIAQABNQAECgoKHwACAGQVAA==.',
Ge='Geauxt:BAAANQAECgUICAABNQAFFAUIHAAMABkaAA==.',
Gl='Glenlizzo:BAAANQADCgEJAQABNQAECgMIBgARAAAAAA==.Glenroyce:BAAANQAECgMIBgAAAA==.Gless:BAABNQAECn80AAMHAAkKsgvFDwA5AQAHAAkKsgvFDwA5AQALAAEKAAC1XwEnAAAAAA==.',
Gn='Gnoretreat:BAABNQAECn8zAAILAAoKihhNQADOAQALAAoKihhNQADOAQAAAA==.',
Go='Goss:BAAANQAECggICAAAAA==.',
Gw='Gwinnivor:BAAANQAECgIIAgAAAA==.',
Ha='Haenus:BAAANQADCgMIAwAAAA==.Haill:BAAANQAECgQIBQABNQAECgcIFwACAN8bAA==.Hamhock:BAAANQAECgIIAgABNQAECgkJMwAIAIIfAA==.Hanis:BAAANQADCgQIBAAAAA==.',
He='Hellìos:BAAANQADCgYIBgABNQAECgIIAgARAAAAAA==.',
Hy='Hyborian:BAABNQAECn8cAAIDAAcKCw3RgAAxAQADAAcKCw3RgAAxAQABNQADCgIIAgARAAAAAA==.',
Ic='Icandy:BAAANQADCgMIAgAAAA==.Icecuber:BAAANQADCgUIBwAAAA==.',
Ih='Ihatepallys:BAAANQADCgYICQAAAA==.',
Ii='Iikeomgikr:BAABNQAECn8oAAIWAAoKohEeMAAAAgAWAAoKohEeMAAAAgAAAA==.',
Il='Ilidank:BAABNQAECn8WAAIOAAgK4yA8BwCYAgAOAAgK4yA8BwCYAgAAAA==.Ilya:BAAANQAECgcIBwAAAA==.',
In='Indigo:BAABNQAECn8oAAICAAkK2xogUAAlAgACAAkK2xogUAAlAgAAAA==.Ineffablyss:BAAANQAECgYIBwABNQAECgoKKAAWAKIRAA==.Innron:BAABNQAECn8uAAIaAAoKMwweIwB8AQAaAAoKMwweIwB8AQAAAA==.',
Io='Iol:BAAANQADCgIIAgAAAA==.',
Ir='Irisblue:BAAANQADCgYIAwAAAA==.',
Ja='Jaque:BAAANQADCgYIDwAAAA==.',
Je='Jeybieber:BAAANQAECgEIAwAAAA==.Jezzea:BAAANQADCgYICwAAAA==.',
Ji='Jinjix:BAAANQADCgYIDQAAAA==.',
Jo='Jolenee:BAAANQAECgEIAQAAAA==.Jolike:BAAANQAECgEIAgAAAA==.Jonly:BAAANQADCgQIBwAAAA==.Jonoa:BAAANQAECgYIDgAAAA==.',
['Jú']='Júdgemental:BAABNQAECn8gAAMNAAkKVhbuTAA2AgANAAkKVhbuTAA2AgAbAAQKMBWVyADOAAAAAA==.',
Ka='Kaelae:BAAANQAECgEIAgABNQAECgoKLAAWANYiAA==.Kair:BAAANQADCgcIBwAAAA==.Kalsium:BAAANQADCgUJDAAAAA==.Kami:BAAANQAECgIIAwAAAA==.Kattastrophy:BAAANQAECgEIAQAAAA==.Katteya:BAAANQAECgQIBAAAAA==.Kattia:BAABNQAECn80AAIDAAkK1wfQXwB/AQADAAkK1wfQXwB/AQAAAA==.',
Ki='Killinkair:BAAANQAECgYIEwAAAA==.Kinomihime:BAABNQAECn8yAAMTAAoKJRDqDQDPAQATAAoKJRDqDQDPAQAFAAEKMAa+xwE0AAAAAA==.Kirajoy:BAABNQAECn8zAAMGAAkK/QXiMwD0AAAEAAgKvwU+ZwAyAQAGAAcKYwLiMwD0AAAAAA==.Kisses:BAAANQAECgEIAQAAAA==.',
Kn='Knyghtt:BAABNQAECn8YAAIIAAkKZwioFQBCAQAIAAkKZwioFQBCAQAAAA==.',
Kr='Kraviz:BAAANQADCgcICgAAAA==.Krombopolous:BAAANQADCggIBwABNQAECggILQADACMMAA==.Krystle:BAAANQAECgcIDQAAAA==.',
Le='Leftyloose:BAAANQADCgYIBAAAAA==.Leorna:BAAANQADCgQIBQAAAA==.',
Li='Lightcure:BAAANQAECgQICAABNQAECggIDQARAAAAAA==.Lilfonz:BAAANQAECgYIEAAAAA==.Lishalan:BAAANQAECgYIBwAAAA==.Littlejohn:BAAANQAECgQIBwABNQAECggIFgAOAOMgAA==.',
Lo='Logarth:BAAANQAECgYIDAAAAA==.Londonfog:BAAANQAECgEIAQAAAA==.Loppandload:BAAANQAECgEIAQAAAA==.Loppsang:BAAANQAECgIIAgAAAA==.Lorcan:BAABNQAECn81AAILAAoK3x9NPgDXAQALAAoK3x9NPgDXAQAAAA==.',
Lr='Lroye:BAACNQAFFH8cAAMMAAUKGRofBwCdAQAMAAUKGRofBwCdAQAcAAEK2w0uIABIAAA1AAQKf0QAAwwACgrkJFQCAI8DAAwACgrkJFQCAI8DABwAAQrOG7JKAFcAAAAA.',
Lu='Lucyfer:BAAANQADCgcIDQABNQAECgYIFAAFAM0CAA==.Lucyferr:BAABNQAECn8UAAIFAAYKzQK5ggG/AAAFAAYKzQK5ggG/AAAAAA==.Ludicrispeed:BAAANQADCgYIAwAAAA==.Luliak:BAAANQAECgIIAwABNQAFFAQICwAZAGIiAA==.Lunabren:BAAANQADCgcIBgAAAA==.Lunamina:BAAANQAECgEIAQAAAA==.',
['Lì']='Lìllith:BAABNQAECn8WAAMWAAgKjA18lwBPAQAWAAcKrQx8lwBPAQAdAAYKfgoaJADmAAABNQAECgoKOwAbAJseAA==.',
Ma='Madoka:BAABNQAECn8qAAILAAoKUxLpRAC7AQALAAoKUxLpRAC7AQAAAA==.Mardreaux:BAAANQAECgEIAwAAAA==.Mariophra:BAABNQAECn8eAAICAAgKKxMNPACpAQACAAgKKxMNPACpAQAAAA==.Maxdemon:BAAANQADCgcIDAAAAA==.Maxpal:BAAANQADCgYIDgAAAA==.',
Mc='Mcnastyqt:BAAANQADCgIIAgAAAA==.',
Me='Mesdel:BAAANQAECgEIAgABNQAECggICAARAAAAAA==.',
Mi='Mikki:BAAANQADCgIIAgAAAA==.Misstorgo:BAAANQAECgMIBQAAAA==.',
Mo='Mohegian:BAAANQABCgQIAwAAAA==.Mokoko:BAAANQAECggIEAAAAA==.Momoka:BAAANQAECgYIDgAAAA==.Monfro:BAAANQAECgYICQAAAA==.Monnethir:BAAANQADCgUIBQAAAA==.Moogatoo:BAAANQAECgEIBAAAAA==.Moonbane:BAABNQAECn8xAAMGAAkKXh3+BQCwAgAGAAkKXh3+BQCwAgAEAAQKZAzL+wDUAAAAAA==.Moonmist:BAAANQAECgEIBAABNQAECgcIFwACAN8bAA==.Mordecai:BAABNQAECn8WAAIDAAkKpBqraQBAAgADAAkKpBqraQBAAgAAAA==.',
My='Myaquean:BAAANQADCgYIDgAAAA==.Mystogan:BAAANQADCgYIDgAAAA==.Myth:BAABNQAECn8nAAMPAAkK3hX9NwAuAgAPAAkK3hX9NwAuAgAQAAQKnBLPQgCFAAAAAA==.Mythelea:BAAANQADCggIDQAAAA==.',
Na='Naavi:BAAANQAECgQIBQAAAA==.Nakeefa:BAAANQAECgEIAgAAAA==.Natsuu:BAABNQAECn8tAAMDAAkK+hB5TAC3AQADAAkK+hB5TAC3AQAeAAIK1wNHDABPAAAAAA==.',
Ne='Nefertiti:BAAANQADCggIAwAAAA==.Nekona:BAAANQADCgQIBAAAAA==.Neron:BAABNQAECn87AAIbAAoKmx7LMQAEAwAbAAoKmx7LMQAEAwAAAA==.',
Ni='Niany:BAAANQAECgMIBgAAAA==.',
Nj='Njoror:BAAANQAECgIIAwAAAA==.',
No='Nonoffensive:BAAANQADCggIDwAAAA==.Norky:BAAANQAECgEIAQABNQAECgIIAgARAAAAAA==.Nottapally:BAAANQAECggIDAABNQAECgoKGwANAKwSAA==.Noxxon:BAAANQAECgEIAgAAAA==.',
Or='Orophin:BAAANQAECgEIAQABNQAECgEIBAARAAAAAA==.',
Os='Ossiferous:BAAANQAECgYIEAAAAA==.',
Ou='Outerlimits:BAABNQAECn8YAAIUAAoKrw4cSwCNAQAUAAoKrw4cSwCNAQAAAA==.',
Pa='Pamboo:BAABNQAECn86AAINAAoKigyJOQC2AQANAAoKigyJOQC2AQAAAA==.Patticake:BAAANQAECggICQAAAA==.',
Pe='Pearle:BAAANQAECggICAAAAA==.Penthesilea:BAAANQABCggICQAAAA==.',
Po='Potatoslicer:BAAANQADCgQIBAAAAA==.',
Pr='Priestiô:BAAANQAECgUIDQAAAA==.Pringo:BAABNQAECn8UAAIFAAgKnwQ+yQC6AAAFAAgKnwQ+yQC6AAAAAA==.',
Py='Pylea:BAAANQAECgIIBQAAAA==.',
Qa='Qahnaarin:BAAANQAECgEIAQAAAA==.',
Ra='Ramindizzle:BAABNQAECn8xAAIfAAoKexAAGABKAQAfAAoKexAAGABKAQAAAA==.Randomname:BAABNQAECn8bAAIDAAkKLRdoVACfAQADAAkKLRdoVACfAQABNQAECgkJIAANAFYWAA==.',
Re='Refreshing:BAAANQADCggIDwAAAA==.Rekki:BAAANQAECgQICwABNQAECgYIFAAFAM0CAA==.Retastic:BAAANQADCgUIBQAAAA==.',
Ri='Rigmarole:BAAANQAECgcIEAAAAA==.',
Ro='Rocksmasher:BAAANQADCgEIAQABNQAECgoKGwANAKwSAA==.Ronun:BAAANQADCggICwAAAA==.Roograh:BAAANQAECgEIAQAAAA==.Rook:BAAANQAECgEIAQAAAA==.Rooklyn:BAABNQAECn81AAINAAoKJRL8MQDaAQANAAoKJRL8MQDaAQAAAA==.Roye:BAACNQAFFH8FAAIbAAUKkRVTCwDrAAAbAAUKkRVTCwDrAAA1AAQKfzYAAhsACgpoIYQVANACABsACgpoIYQVANACAAE1AAUUBQgcAAwAGRoA.',
Ru='Ruffiyo:BAAANQAECggIDQAAAA==.Rugrahh:BAAANQADCgYIBgABNQAECgEIAQARAAAAAA==.Rugzco:BAABNQAECn8tAAIgAAoKMRjOEAByAgAgAAoKMRjOEAByAgAAAA==.Ruìn:BAAANQAECgUICgAAAA==.',
Ry='Ryalla:BAAANQABCgEIAQAAAA==.',
['Ræ']='Ræñ:BAAANQAECgcICAAAAA==.',
Sa='Sabina:BAABNQAECn8wAAIhAAoKYghOjQCDAQAhAAoKYghOjQCDAQAAAA==.Sadako:BAAANQAECgEIAgABNQAECgYIFAAFAM0CAA==.Sadness:BAAANQADCggIIAAAAA==.Sadorick:BAAANQAECgQIBAAAAA==.Sadôrick:BAAANQADCggIBwAAAA==.Sageguy:BAAANQADCgcIDwAAAA==.Saintkitiara:BAAANQABCgMIAwAAAA==.Sango:BAABNQAECn8uAAIaAAoKwRMOFgD8AQAaAAoKwRMOFgD8AQAAAA==.Sarenity:BAAANQADCgcIDQAAAA==.Savagelykill:BAAANQADCggIDgAAAA==.',
Sc='Scotch:BAABNQAECn8tAAMbAAkK5hFIpADYAQAbAAkK5hFIpADYAQAJAAMKkRFjSwAyAAAAAA==.Scotchnwater:BAAANQAECgcICQAAAA==.Scratchies:BAABNQAECn8bAAIQAAoKchFHFQDWAQAQAAoKchFHFQDWAQAAAA==.',
Se='Seiwar:BAABNQAFFH8GAAILAAMKqAd9KAC5AAALAAMKqAd9KAC5AAAAAA==.Serebus:BAAANQAECgEIAQAAAA==.',
Sh='Shadornia:BAAANQAECgMICQAAAA==.Shadowcrwlr:BAAANQADCgQIBAAAAA==.Shamangroo:BAAANQAECgEIAQAAAA==.Shamanio:BAABNQAECn81AAMCAAoKhCQLCwBoAwACAAoKhCQLCwBoAwAhAAEKCxQMtQBBAAAAAA==.Shammbulance:BAAANQAECggIEgABNQAECgkJIAANAFYWAA==.Sharaaz:BAAANQADCgUIBQAAAA==.Shatoya:BAAANQADCgcIAwAAAA==.',
Si='Silverytwo:BAAANQADCggIFgAAAA==.Silverywolfe:BAAANQAECgQIBQAAAA==.Simony:BAAANQADCggICAABNQAECgYIFAAFAM0CAA==.Sintia:BAAANQAECgYIDQABNQAECgoKLAAWANYiAA==.',
Sk='Skovak:BAAANQAECgUIBwAAAA==.Skoveth:BAAANQAECgIIBAAAAA==.',
So='Sorayae:BAABNQAECn8sAAIWAAoK1iLyCAB8AwAWAAoK1iLyCAB8AwAAAA==.',
Sp='Specialk:BAAANQAECgQIBQAAAA==.Splooshh:BAAANQADCggIDgABNQAECggIDQARAAAAAA==.',
St='Steeler:BAAANQAECgEIAgABNQADCgIIAgARAAAAAA==.Stinkfoot:BAABNQAECn8dAAIBAAgKgxWlSQDRAQABAAgKgxWlSQDRAQAAAA==.Stormkissed:BAAANQAECgMIBQAAAA==.Strawman:BAAANQAECggIEwAAAA==.',
Su='Sugarush:BAAANQAECgEIAQABNQAECgcIFwACAN8bAA==.Sulvazud:BAAANQADCgEIAQAAAA==.Sunil:BAABNQAECn8uAAIWAAkKTRhNJgA4AgAWAAkKTRhNJgA4AgAAAA==.',
Sy='Syclone:BAAANQAECgMIBgABNQAFFAIICAABAL0fAA==.Sypha:BAAANQAECgYIEAAAAA==.',
Ta='Taetheras:BAAANQAECgUIDQAAAA==.Tahlyn:BAAANQAECgcICQABNQAECgkJKAACANsaAA==.Tattianna:BAAANQADCggIGQAAAA==.Tavendar:BAABNQAECn8sAAMNAAoKURzYKAAMAgANAAkK3hvYKAAMAgAbAAIKSwV0jAFJAAABNQAECgIIAgARAAAAAA==.Taírn:BAAANQADCgEIAQABNQAECgoKLAAZAHccAA==.',
Tc='Tcshmaster:BAAANQAECgIIBQAAAA==.',
Te='Texgrebner:BAAANQAECgYIDgABNQAECggIFgAOAOMgAA==.',
Th='Theeyedoctor:BAAANQADCggIBwABNQAECgoKGwANAKwSAA==.Thunderslate:BAABNQAECn8bAAMNAAoKrBKDJgAaAgANAAkK0BODJgAaAgAJAAYKmxD+MgBKAQAAAA==.Thyrok:BAAANQAECggIDwAAAA==.',
Ti='Tigreth:BAABNQAECn82AAMbAAoKbwyttQCzAQAbAAoKbwyttQCzAQAJAAUK+wenWQB3AAAAAA==.Tinkerballa:BAAANQADCggJEgAAAA==.',
To='Toastal:BAAANQAECgIIAgAAAA==.Tokxi:BAAANQADCgIIAgABNQAECgoKIwAJAMUVAA==.Totemzasap:BAAANQAECgQICAAAAA==.',
Tr='Traductus:BAAANQAECgMIAwAAAA==.Tragik:BAABNQAECn83AAIZAAoKgAqNDADMAQAZAAoKgAqNDADMAQAAAA==.Treetrunkz:BAAANQAECgEIAQAAAA==.Trisandra:BAAANQAECgMIBQAAAA==.',
Tu='Tuugadark:BAABNQAECn8wAAIEAAoKYBpfNwCuAgAEAAoKYBpfNwCuAgAAAA==.Tuugashox:BAAANQAECgEIAQAAAA==.',
Tz='Tzulari:BAAANQAECgUICAAAAA==.',
Ul='Ulyaoth:BAAANQADCgUIBQAAAA==.',
Un='Unbroken:BAAANQADCgMIAwAAAA==.Unprepared:BAAANQAECgEIAQABNQAECgcIIAAFAGkTAA==.',
Va='Vasdeferens:BAAANQABCgMIAwAAAA==.',
Ve='Vedros:BAAANQADCgYICQAAAA==.Verbina:BAAANQAECgUIEQABNQAECgkJKAACANsaAA==.',
Vo='Vorukh:BAAANQAECgIIBQAAAA==.',
Vy='Vynas:BAAANQAECgIIAgAAAA==.',
Wa='Warlockgroo:BAAANQADCgcICgABNQAECgEIAQARAAAAAA==.Warriorgroo:BAAANQAECgEIAQABNQAECgEIAQARAAAAAA==.',
Wh='Whácker:BAAANQAECgIIAgABNQAECgoKLAAZAHccAA==.',
Wi='Wickdlovly:BAAANQAECgEIAQABNQAECgcIFwACAN8bAA==.Wickedslicks:BAABNQAECn8YAAIPAAcKlx0rQgDuAQAPAAcKlx0rQgDuAQAAAA==.',
Wr='Wreckshop:BAAANQADCgYIDwABNQAECggIJgAKAGceAA==.',
Xe='Xenøcide:BAAANQADCgcICwAAAA==.',
Xi='Xiatus:BAAANQAECgcIEwABNQAECgoKRAAiAFolAA==.',
Xo='Xoren:BAAANQAECgEIAgABNQAECgYIFAAFAM0CAA==.',
Xx='Xxdeathz:BAAANQABCgMIAwABNQAECggIGgANANwbAA==.Xxlockz:BAAANQAECgQIBAABNQAECggIGgANANwbAA==.Xxpallyz:BAABNQAECn8aAAINAAgK3BsNTwAvAgANAAgK3BsNTwAvAgAAAA==.',
Yo='Yohh:BAABNQAECn8qAAICAAkKkxN2SwA1AgACAAkKkxN2SwA1AgAAAA==.Yorie:BAAANQADCgMIAwAAAA==.',
Yu='Yuriko:BAABNQAECn82AAMgAAoK6A+YEAByAQAgAAoK6A+YEAByAQAjAAEK4wXCHgAsAAAAAA==.',
Za='Zadory:BAAANQADCggIDAAAAA==.Zaidan:BAAANQAECgEIAQAAAA==.',
Ze='Zendous:BAAANQAECgYIBgAAAA==.',
Zi='Zippitydooda:BAABNQAECn8XAAICAAcK3xseQQCTAQACAAcK3xseQQCTAQAAAA==.',
Zo='Zodiacc:BAABNQAECn82AAISAAoKPSAICAD/AgASAAoKPSAICAD/AgAAAA==.Zornhealer:BAAANQADCggICAABNQAECgcIDAARAAAAAA==.Zorrn:BAAANQAECgcIDAAAAA==.',
['Zí']='Zílch:BAAANQAECgEIAQAAAA==.',
['Zî']='Zîlch:BAAANQADCgcIBwAAAA==.',
['Zö']='Zölä:BAAANQAECgQICAABNQAECgYICAARAAAAAA==.',
['Çh']='Çhrìs:BAAANQAECgQICgAAAA==.',
['Çú']='Çúrsè:BAAANQADCgIIAwAAAA==.',
['Èn']='Èntity:BAAANQAECgcIDgAAAA==.',
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
