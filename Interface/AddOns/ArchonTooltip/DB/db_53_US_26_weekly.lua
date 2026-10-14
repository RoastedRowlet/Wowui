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

local lookup = {'Druid-Restoration','Unknown-Unknown','Priest-Holy','Warlock-Affliction','Paladin-Protection','Paladin-Retribution','Warlock-Demonology','Mage-Frost','Mage-Arcane','Druid-Balance','Warrior-Fury','DemonHunter-Havoc','Warrior-Arms','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Hunter-BeastMastery','Monk-Windwalker','Warlock-Destruction','Warrior-Protection','Monk-Brewmaster','Hunter-Marksmanship','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Blood','Shaman-Elemental','Monk-Mistweaver','Mage-Fire','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Priest-Discipline','Druid-Guardian','DemonHunter-Vengeance','Evoker-Devastation','Druid-Feral','Evoker-Preservation','DemonHunter-Devourer',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaryyee:BAAANQAECgEIAQAAAA==.',
Ac='Acaeus:BAAANQABCgQIBQAAAA==.Aceforlife:BAABNQAECn8jAAIBAAYKLQgiSADuAAABAAYKLQgiSADuAAAAAA==.',
Ad='Adrox:BAAANQADCgMIBAAAAA==.',
Ae='Aelelelos:BAAANQADCgcICgAAAA==.Aequus:BAAANQABCgUIAwAAAA==.Aevenyhm:BAABNQAECn8kAAIBAAgKkxmqHgA0AgABAAgKkxmqHgA0AgAAAA==.',
Ag='Aghorn:BAAANQAECgEIAgAAAA==.',
Ai='Aidoneus:BAAANQADCgYIBgABNQAFFAEIAQACAAAAAA==.',
Ak='Akijin:BAAANQABCgQIBAABNQAECgcIEQACAAAAAA==.Akismite:BAAANQAECgcIEQAAAA==.',
Al='Alaru:BAABNQAECn8gAAIDAAgKRApUhgB/AQADAAgKRApUhgB/AQAAAA==.Alemental:BAAANQADCgcIEgABNQAECgYIDQACAAAAAA==.Algana:BAAANQADCggIDQABNQAECggIKAAEAN0SAA==.Allhallows:BAAANQAECgUIDgAAAA==.Alorandis:BAAANQAECgIIAgAAAA==.Alqueria:BAABNQAECn8iAAMFAAkKpReFGwAPAgAFAAgKLhiFGwAPAgAGAAgKYg9ctACwAQABNQAECgkJLAAHAA4cAA==.Altarboizyum:BAAANQAECgIJAQABNQAECgkJNwAFAGkhAA==.',
An='Andanto:BAAANQAECgUIEAAAAA==.Angeliz:BAAANQAECgcIDAAAAA==.Anitaloc:BAAANQAECgQIBgAAAA==.Anneweaver:BAABNQAECn8pAAMIAAkK6h6ZDwCsAQAJAAkKjByGeQCLAgAIAAgKGhuZDwCsAQABNQAFFAYIEwAJAK8NAA==.Anorantha:BAABNQAECn8sAAIKAAkK+wrXRwDIAQAKAAkK+wrXRwDIAQAAAA==.',
Ap='Apicots:BAAANQADCggIDwAAAA==.Apipa:BAAANQAECgYIBwAAAA==.Apricot:BAAANQADCgUIBQAAAA==.Apzz:BAAANQADCgIIAgAAAA==.',
Ar='Arizticat:BAAANQADCgUICQAAAA==.Arrowin:BAAANQADCgQIBAAAAA==.Artica:BAAANQADCggICAAAAA==.Arzan:BAAANQAECgEIAQAAAA==.',
As='Ashalan:BAAANQAECgUIDwAAAA==.Ashenflail:BAAANQAECgUICAAAAA==.Asherabinx:BAAANQABCgYIDgAAAA==.Astesia:BAAANQAECgYIBgAAAA==.Astrraa:BAAANQADCggIEAAAAA==.Asulo:BAAANQAECgYIBgABNQAFFAMICAALAFAbAA==.',
At='Atrejha:BAACNQAFFH8FAAIMAAIKWgiJGAB2AAAMAAIKWgiJGAB2AAA1AAQKfx8AAgwACQoyCpQ+AMEBAAwACQoyCpQ+AMEBAAAA.',
Au='Aurä:BAABNQAECn8aAAIJAAgKlQ1B0wDdAQAJAAgKlQ1B0wDdAQABNQAECgkJFwANAEQUAA==.Aussilio:BAAANQADCggICAAAAA==.',
Av='Avera:BAAANQAECgEIAQAAAA==.',
Aw='Awesome:BAAANQAECgQIBQAAAA==.',
Az='Azgkrimpatul:BAAANQADCgYICwAAAA==.Azmodeus:BAAANQADCgUIBwAAAA==.Azrina:BAAANQAECgcIEwAAAA==.',
Ba='Bael:BAAANQAECggIEQAAAA==.Baidden:BAAANQADCgMIBQAAAA==.Balddk:BAAANQAECgYIEQABNQAECgcIGgAJAEURAA==.Baldrogue:BAACNQAFFH8JAAIOAAMKbht6DgD9AAAOAAMKbht6DgD9AAA1AAQKfyUABA4ACQppIG8JAEEDAA4ACQpjIG8JAEEDAA8ACApwDgMcAPIBABAACArtAlAQABgBAAAA.Baldwarrior:BAABNQAECn8jAAINAAkKJRfbVQCGAgANAAkKJRfbVQCGAgAAAA==.Ballflapper:BAAANQADCgcICAABNQAECgkJFwARAPAMAA==.Bandidos:BAAANQAECgQIBQAAAA==.Banekin:BAAANQADCggICAAAAA==.',
Be='Beastmans:BAAANQADCgQIBAAAAA==.Becka:BAAANQAECgUIBgAAAA==.Beckz:BAAANQADCggIDQAAAA==.Beefhambacon:BAAANQAECgUIDgAAAA==.Behealzabub:BAAANQAECgYIDAAAAA==.Beladora:BAAANQADCgEIAQAAAA==.Belmatride:BAAANQAECgIIBwAAAA==.Belpepper:BAABNQAECn8VAAIGAAkKxwpytQCtAQAGAAkKxwpytQCtAQAAAA==.Bendelmonte:BAAANQADCggIIgABNQAECgUIEwACAAAAAA==.',
Bi='Biggum:BAAANQADCgIIAgAAAA==.Bigmez:BAAANQAECgUICQAAAA==.Bigmoocowii:BAAANQADCgIIAgAAAA==.Bigswangindi:BAAANQADCggIEAAAAA==.Bilipmonk:BAABNQAECn8YAAISAAkKLxNEIgATAgASAAkKLxNEIgATAgAAAA==.Bindinglight:BAACNQAFFH8HAAMKAAIKYgQDIgB/AAAKAAIKYgQDIgB/AAABAAEKdwXeFwA5AAA1AAQKf0cAAwEACQqQFuEYAHICAAEACQqQFuEYAHICAAoACQrFEjI0AEMCAAAA.Birdofhermes:BAAANQADCgMIAwAAAA==.Bizzthewizz:BAAANQADCgQIBAAAAA==.Biñx:BAAANQABCgQJCQAAAA==.',
Bl='Blarr:BAAANQAECgYICAAAAA==.Blindehunter:BAAANQADCgIIAgABNQADCgIIAgACAAAAAA==.Blindvoid:BAAANQAECgIIAgABNQADCgIIAgACAAAAAA==.Bloodguard:BAAANQADCgYIBgAAAA==.Blubinax:BAAANQADCgQIBAAAAA==.Bluedabodeba:BAAANQADCgEIAQAAAA==.Bluejeanz:BAAANQADCgYIBQABNQAECgkJIAAKABIiAA==.',
Bo='Bodom:BAAANQABCgUIBQAAAA==.Boonkay:BAAANQADCgEIAQAAAA==.Boonkie:BAAANQAECggIAQAAAA==.Boonksdragon:BAAANQAECggICAAAAA==.Boonlock:BAAANQAECggIAQAAAA==.Boreowlis:BAAANQABCgQICAAAAA==.Boxbeater:BAAANQADCgYIBgAAAA==.',
Br='Braedravia:BAAANQADCgIIAgAAAA==.Bretikus:BAAANQAECgYIBgAAAA==.Brisanna:BAAANQAECgYIDQAAAA==.Bruleecreme:BAAANQADCgcIBwAAAA==.',
Bu='Bubos:BAAANQADCgIJAgAAAA==.Budgeroo:BAAANQAECgUIBAAAAA==.',
['Bà']='Bàwlz:BAAANQAECgYIEgAAAA==.',
['Bè']='Bèérsërk:BAAANQADCgEIAQAAAA==.',
['Bö']='Böðull:BAAANQAECgMIAwAAAA==.',
Ca='Caelix:BAAANQADCgQIBQAAAA==.Caledor:BAABNQAECn8bAAIGAAgK5w9ImgDpAQAGAAgK5w9ImgDpAQAAAA==.Calkhan:BAAANQADCgMIAwAAAA==.Camitriel:BAABNQAECn+WAQMHAAgK7yZgBQClAwAHAAgK7yZgBQClAwATAAQKAyV+GACnAQAAAA==.Cataleya:BAAANQAECggIAgAAAA==.',
Ce='Ceaserianoma:BAAANQADCgMIAwAAAA==.',
Ch='Chadder:BAAANQAECggIEAAAAA==.Charliie:BAABNQAECn8lAAMUAAkKlx+JBAA7AwAUAAkKlx+JBAA7AwANAAEKxA1kRgE9AAAAAA==.Chaunakoala:BAAANQADCgIIAgAAAA==.Cherryfudge:BAAANQADCggIDQAAAA==.Chipinwing:BAAANQAECgEIAQAAAA==.Chunkysoupz:BAAANQADCgYIBgAAAA==.',
Cl='Classyshammy:BAAANQADCggIDAAAAA==.Clockworks:BAAANQADCgcIEwAAAA==.Clouxdyskies:BAAANQADCgEIAQAAAA==.',
Co='Cocinegr:BAABNQAECn8aAAIHAAcK9QwPrAB0AQAHAAcK9QwPrAB0AQABNQAFFAMICwAJAOgWAA==.Cocinegrø:BAAANQAECggIBgABNQAFFAMICwAJAOgWAA==.Cokuzo:BAAANQADCggICQAAAA==.Coneja:BAABNQAECn8qAAIJAAgKxQrA3QDJAQAJAAgKxQrA3QDJAQAAAA==.Coolbroguy:BAAANQABCgQIBAAAAA==.Coomspit:BAAANQAECgIIAgAAAA==.Corwa:BAAANQAECgEIAQABNQAECgkJHAAGALggAA==.Covidnynteen:BAAANQADCgUICAAAAA==.Cowtastrophe:BAAANQABCgcIEAAAAA==.',
Cr='Craiso:BAABNQAECn8bAAIVAAcKfiKpCACdAgAVAAcKfiKpCACdAgAAAA==.Crankinhawg:BAAANQAECgcIEwAAAA==.Crazbezzul:BAAANQADCgUIBwAAAA==.Creationz:BAAANQADCgYICQABNQAECgEJAQACAAAAAA==.Crisarrow:BAAANQADCggIGAAAAA==.',
Cu='Current:BAABNQAECn8YAAIMAAgKoQXgUABOAQAMAAgKoQXgUABOAQAAAA==.',
Cy='Cynesh:BAACNQAFFH8ZAAMRAAcKUR/LAwAfAgARAAYKDyLLAwAfAgAWAAUKSRV3DAByAQA1AAQKfyIAAxEACQrDJQIVAEcDABEACQq3JQIVAEcDABYABwqvIDUpAP4BAAAA.Cytl:BAAANQAECgYICwAAAA==.',
Da='Dailybuilt:BAAANQADCgQICgAAAA==.Damitbobbi:BAAANQADCgUIBQAAAA==.Dangybangy:BAABNQAECn8YAAIRAAcKXhHOlgDWAQARAAcKXhHOlgDWAQAAAA==.Danjaianka:BAAANQADCggJHgAAAA==.Dankshotzs:BAAANQABCggICwAAAA==.Darkken:BAAANQADCgYJBgABNQADCgcIEwACAAAAAA==.Darkkragmur:BAAANQAECgUICAAAAA==.Darknest:BAAANQADCgQIBgAAAA==.Darthimus:BAAANQAECgIIAwAAAA==.Datbishkarma:BAABNQAECn8aAAIJAAcKHAW7IAFRAQAJAAcKHAW7IAFRAQAAAA==.',
Dd='Dding:BAABNQAECn8sAAMFAAkKhiUXAgCyAwAFAAkKhiUXAgCyAwAGAAEKEwGE4wEEAAAAAA==.',
De='Deadbarcy:BAAANQAECgIJAgAAAA==.Deathklok:BAABNQAECn8bAAMXAAkKEBOzUgAYAgAXAAkKEBOzUgAYAgAYAAYKhAQ4IwAhAQAAAA==.Deathran:BAABNQAECn8jAAIHAAgKcxs5WgBFAgAHAAgKcxs5WgBFAgAAAA==.Deezgrips:BAABNQAECn8kAAIZAAgKvxo7JgCJAgAZAAgKvxo7JgCJAgAAAA==.Deffgwip:BAAANQAECgYIEQAAAA==.Delfine:BAAANQADCggIHQAAAA==.Demonikiarly:BAAANQADCgUJBQABNQAECgYIDAACAAAAAA==.Desimus:BAAANQADCgcICgAAAA==.Despott:BAABNQAECn8aAAIJAAcKRRFU3ADMAQAJAAcKRRFU3ADMAQAAAA==.Destina:BAAANQAECgcIDwAAAA==.Dethfox:BAAANQAECgUIEwAAAA==.Dethlock:BAAANQADCgQIBAAAAA==.',
Di='Dioni:BAABNQAECn8lAAMXAAgKSCK0HgDuAgAXAAgKSCK0HgDuAgAaAAYKgAq7rgAxAQABNQAECgkJJgABANQcAA==.Dirknasty:BAAANQAECgQIBwAAAA==.Diyfootjobs:BAAANQADCgYJGgAAAA==.',
Dk='Dkurther:BAAANQAECgUIDQAAAA==.',
Do='Doggybag:BAAANQADCgQIBAAAAA==.Doomhauerr:BAAANQAECggICAAAAA==.Dottonohana:BAAANQAECgQIBAAAAA==.Doublehelix:BAAANQAECgcIDQAAAA==.Dovish:BAAANQAECgcIDAAAAA==.',
Dr='Drackygacky:BAAANQAECgEIAwAAAA==.Dracw:BAAANQAECgUIBgAAAA==.Draglox:BAAANQAECgQIBAAAAA==.Drakaryss:BAAANQADCgEIAQABNQAECgkJMgAbAGkkAA==.Drama:BAAANQAECgEIAQAAAA==.Drashar:BAAANQADCgUIBQAAAA==.Dravenm:BAABNQAECn8dAAIJAAcKjA457QCtAQAJAAcKjA457QCtAQAAAA==.Draz:BAAANQAECgMIBQAAAA==.Droozh:BAAANQADCgMIAwAAAA==.Drunkendrago:BAAANQADCgcIBwAAAA==.',
Du='Duesenjaeger:BAAANQADCgcICwAAAA==.Duko:BAAANQADCgEIAQAAAA==.',
['Dè']='Dèmonic:BAAANQAFFAEIAQAAAA==.',
['Dé']='Désy:BAAANQAECgMIAwAAAA==.',
['Dø']='Døric:BAAANQADCgcJDAAAAA==.',
['Dü']='Dürinn:BAAANQADCgIIAgAAAA==.',
Eh='Ehud:BAABNQAECn8qAAIGAAkKiSMCDACgAwAGAAkKiSMCDACgAwAAAA==.',
Ei='Eisiss:BAAANQABCgEIAQAAAA==.',
Ek='Ekô:BAAANQADCggIDgAAAA==.',
El='Elabrate:BAAANQADCgMIAwAAAA==.Elade:BAAANQADCgUIBQAAAA==.Elbori:BAABNQAECn8eAAIcAAkKeBWkAQCIAgAcAAkKeBWkAQCIAgAAAA==.Elbryan:BAAANQADCgMIAwAAAA==.Eldaral:BAAANQAECggIBAAAAA==.Elementium:BAAANQAECgcIDgAAAA==.Elfmas:BAAANQAECgYICQAAAA==.Elorees:BAAANQADCgYIBgAAAA==.Elviswong:BAAANQADCgIIAgAAAA==.',
Em='Emerhy:BAAANQAECgEJAQAAAA==.',
Es='Escänor:BAABNQAECn8eAAMGAAkKuh7wIwAzAwAGAAkKuh7wIwAzAwAFAAIKfwmrZQBHAAAAAA==.Eshaia:BAAANQADCgEIAQAAAA==.',
Ex='Exlisum:BAAANQADCgQIBgAAAA==.',
Ey='Eyewyn:BAAANQABCgYIBQAAAA==.Eylos:BAAANQADCggIDAAAAA==.',
Fa='Faesmite:BAAANQADCgUIBQAAAA==.Faithflop:BAAANQAECgYIEAAAAA==.Falleh:BAAANQADCgIIAgAAAA==.Fanorage:BAAANQAECgIIAgAAAA==.',
Fe='Felixox:BAAANQAECgEIAQAAAA==.Ferocias:BAAANQAECgQJBQAAAA==.Ferraxx:BAAANQADCgcIBwAAAA==.',
Fi='Fiametta:BAAANQADCggICAAAAA==.Fishbreath:BAAANQAECgEIAQAAAA==.',
Fl='Flaffergan:BAAANQAECgYIEQAAAA==.Flastage:BAAANQAECgMIAQAAAA==.Flexhack:BAABNQAECn8VAAIPAAcKHws5KAB/AQAPAAcKHws5KAB/AQAAAA==.Flåsh:BAABNQAECn8fAAMdAAgK8SBXNACQAgAdAAcK+SBXNACQAgAGAAcK9BUClQD1AQAAAA==.',
Fo='Focinnet:BAABNQAECn8nAAIRAAgKVwrEiAD2AQARAAgKVwrEiAD2AQAAAA==.Forandra:BAAANQAECgIIAgAAAA==.Fortyacres:BAAANQADCgEIAQAAAA==.Fortybmh:BAAANQADCgEIAQABNQADCgEIAQACAAAAAA==.Four:BAAANQADCgYJDgAAAA==.Fourform:BAAANQADCgIIAgAAAA==.',
Fr='Frieren:BAAANQAECgUIBgAAAA==.',
Fu='Fuzzbutt:BAAANQADCgEIAQAAAA==.',
Ga='Gaalit:BAAANQADCgcIBwAAAA==.Galaxybone:BAAANQADCgQIBAAAAA==.Galithiri:BAAANQAECgQIAgAAAA==.Ganthani:BAABNQAECn8gAAIDAAcKNhChhACEAQADAAcKNhChhACEAQAAAA==.Garzett:BAABNQAECn8vAAIKAAkKPBi6IgC3AgAKAAkKPBi6IgC3AgAAAA==.Gatortooth:BAAANQABCgIIBAAAAA==.Gaybeowners:BAAANQAECgEJAQAAAA==.',
Ge='Geigh:BAAANQADCgUIBQAAAA==.Gethellar:BAABNQAECn8XAAMRAAkK8AzyigDxAQARAAgKew7yigDxAQAWAAEKqgO3mgAiAAAAAA==.',
Gh='Ghostdaliar:BAAANQADCgQIBgAAAA==.Ghouliana:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.',
Gl='Glizyglober:BAAANQADCgMIAwABNQAFFAIIBwAKAGIEAA==.Glizzyrizily:BAAANQADCgMIAwABNQAFFAIIBwAKAGIEAA==.Glizzyys:BAABNQAECn8dAAINAAgK2QqrrwCgAQANAAgK2QqrrwCgAQABNQAFFAIIBwAKAGIEAA==.Gllizzard:BAAANQADCgMJAwAAAA==.Gluckglucks:BAAANQABCgQIBAAAAA==.',
Go='Gore:BAAANQAECgcIDgAAAA==.Gorrock:BAAANQAECgQIBAAAAA==.',
Gr='Gravtech:BAAANQADCggJDgABNQAECggICgACAAAAAA==.Greenlinaii:BAAANQADCgUIBQAAAA==.Grenzo:BAAANQAECgEIAgAAAA==.Grhm:BAAANQAECgcIBwAAAA==.Grim:BAABNQAECn8hAAMeAAkKOyQAFwACAwAeAAkKMyQAFwACAwAfAAMKyiLmYwAKAQABNQAECgkJIQAKAIAkAA==.Grimheart:BAAANQAECgEIAQAAAA==.Grundles:BAAANQADCggICAAAAA==.Grymnir:BAAANQAECgYIEwAAAA==.',
Gu='Guilliman:BAAANQAECgIIAgAAAA==.Gumsy:BAABNQAECn8aAAMNAAgKSQ4UngDNAQANAAgKzQ0UngDNAQAUAAQKwQzGMQCjAAABNQAECgkJHgAeAPwYAA==.',
Gw='Gwory:BAAANQAECgIIAgAAAA==.',
['Gø']='Gørë:BAAANQAECggIEgAAAA==.',
Ha='Haddassah:BAAANQADCgIIAgAAAA==.Haramzadi:BAAANQADCgQICQAAAA==.Haranue:BAABNQAECn8XAAIRAAUKtAna7gAeAQARAAUKtAna7gAeAQAAAA==.Harryporter:BAAANQAECgEIAQAAAA==.Harukà:BAAANQAECgUIDAAAAA==.',
He='Healscat:BAAANQADCgUJBQAAAA==.Healsdog:BAAANQAECgEIAQAAAA==.Hecâte:BAAANQABCggICgAAAA==.Hefferd:BAAANQADCgQIBAAAAA==.Helfon:BAABNQAECn8lAAIMAAgKMiEoFAD5AgAMAAgKMiEoFAD5AgAAAA==.Helgadknight:BAAANQABCgMIAwAAAA==.Helganelf:BAAANQAECgEIAQAAAA==.Helices:BAABNQAECn8YAAMZAAgKKBnvOwARAgAZAAcKIBvvOwARAgAeAAEKUA9E2AA6AAAAAA==.Herm:BAAANQAECgEIAQAAAA==.',
Hi='Highlordt:BAABNQAECn8jAAQgAAkKsxnLHwA6AgAgAAgKrBvLHwA6AgADAAcK0hPacQDDAQAhAAEKrwfuLQAoAAAAAA==.Highlordtron:BAABNQAECn8UAAQHAAgKuhGgegDwAQAHAAgKdxCgegDwAQATAAEKohIRcQA9AAAEAAEKCwdgLQA7AAAAAA==.Hinoxfine:BAAANQADCgMIBAAAAA==.',
Ho='Holybeast:BAAANQADCgIIAgAAAA==.Holycharge:BAAANQAECgIIAgAAAA==.Holycrab:BAAANQAECgEIAQAAAA==.Holydudy:BAAANQAECgEIAQAAAA==.Holyely:BAAANQAECgUIBwAAAA==.Holyfae:BAABNQAECn8pAAMdAAkK8xPTPwBjAgAdAAkK8xPTPwBjAgAGAAQKbQZOOQG9AAAAAA==.Holygrom:BAABNQAECn8qAAIGAAkKOyVzBwC+AwAGAAkKOyVzBwC+AwAAAA==.Holylove:BAAANQADCgUICgABNQAECgIJAgACAAAAAA==.Holynutzz:BAAANQAECgMIAwAAAA==.Holyrager:BAAANQAECgQIBgAAAA==.Holysplash:BAABNQAECn8cAAIDAAcKiBRVcADIAQADAAcKiBRVcADIAQAAAA==.Holyvoids:BAAANQADCgIIAgAAAA==.Hondodk:BAECNQAFFH8SAAIeAAYKsiTTAABxAgAeAAYKsiTTAABxAgA1AAQKfzMAAx4ACQrJJgADAMUDAB4ACQq+JgADAMUDABkAAQrDJkatAG8AAAE1AAUUBwgTAB4AYyQA.Honeyshamwow:BAAANQAECgMIAwAAAA==.Hoodadin:BAAANQABCgMIAwAAAA==.Hoodlummon:BAAANQADCggJHQAAAA==.Hopesfall:BAAANQAECgIJAwAAAA==.Howzitcuz:BAAANQADCgcIGQABNQAECgcIGgAdAFkZAA==.Hozari:BAABNQAECn8tAAIKAAkKCxhmIwCyAgAKAAkKCxhmIwCyAgAAAA==.',
Ht='Ht:BAAANQADCgcIDAAAAA==.',
['Hã']='Hãvøc:BAAANQADCgIIAgAAAA==.',
Ia='Ianil:BAAANQAECgQIBgAAAA==.',
Ic='Iccyhot:BAAANQADCgMIAwABNQAFFAIIBwAKAGIEAA==.',
Ii='Iiwhiskey:BAAANQADCgcICAAAAA==.',
Il='Ilirranna:BAAANQAECgIIBAAAAA==.',
In='Infi:BAACNQAFFH8cAAMWAAcKpCMwAwBaAgAWAAcK3RwwAwBaAgARAAEKLyUGLQBnAAA1AAQKf0YAAxYACQp8Jk8BANwDABYACQp8Jk8BANwDABEAAQrZJlc2AXAAAAAA.Initabath:BAAANQAECggIEQAAAA==.Initapoop:BAAANQAECgMICQAAAA==.Inosukè:BAABNQAECn8yAAIbAAkKaSTNAQCsAwAbAAkKaSTNAQCsAwAAAA==.Inse:BAAANQAECgMIAwAAAA==.Invisibro:BAAANQAECggICgAAAA==.',
Io='Ioannis:BAAANQAECgUIDgAAAA==.',
Is='Isos:BAABNQAECn8yAAMDAAkKZiKFDgBPAwADAAkKZiKFDgBPAwAhAAEKCBBHKAAzAAAAAA==.Isus:BAAANQADCgYJBgABNQAECgkJMgADAGYiAA==.',
Iy='Iykyk:BAAANQAECgMIAgABNQAECgcIGgAdAFkZAA==.',
Ja='Jadeadly:BAAANQAECgcICAAAAA==.Jaded:BAABNQAECn8oAAISAAkK3BSXHgA5AgASAAkK3BSXHgA5AgAAAA==.Jakerbonk:BAAANQADCgYIBwAAAA==.Jakersai:BAAANQAECgcIEgAAAA==.Jakersaint:BAAANQADCggIDAAAAA==.Javyr:BAAANQAECgYICAAAAA==.Jayfmtv:BAAANQAECgIIAgAAAA==.Jaysdruid:BAAANQAECgQIBAAAAA==.',
Je='Jessicax:BAAANQAECgQIBAAAAA==.Jetpackcat:BAAANQADCgIIAgAAAA==.',
Ji='Jio:BAAANQADCgcIBwAAAA==.',
Jl='Jlnxy:BAABNQAECn8XAAIGAAkK1ApWtwCpAQAGAAkK1ApWtwCpAQAAAA==.',
Jo='Joania:BAAANQADCggICAAAAA==.Jonoa:BAAANQADCgUIBQAAAA==.',
Ju='Judgmentalaf:BAAANQADCggICQAAAA==.Judo:BAAANQAECgEIAQAAAA==.',
Ka='Kadre:BAABNQAECn8XAAIUAAcKSwMmKgDjAAAUAAcKSwMmKgDjAAAAAA==.Kadzilak:BAAANQADCgQIBgAAAA==.Kagemika:BAAANQAECgQIBAABNQAFFAIIBQAMAFoIAA==.Kaiola:BAAANQAECgEIAQAAAA==.Kaizumie:BAAANQAECgIIAgAAAA==.Kalirti:BAAANQADCgIIAgAAAA==.Kamistri:BAABNQAECn8iAAQDAAkKExrOHgDzAgADAAkKExrOHgDzAgAgAAMKCgfSYAB5AAAhAAIKrAb8IgBOAAAAAA==.Kanaa:BAAANQAECgQIBAAAAA==.Kanatre:BAAANQADCgEIAQAAAA==.Kandicee:BAAANQAECgIIAgAAAA==.Karensmith:BAAANQADCgcIBwAAAA==.Karessandra:BAAANQADCgQIBAABNQAECgQIAgACAAAAAA==.Karrison:BAAANQADCgEIAQAAAA==.Kathea:BAAANQAECgQIBAAAAA==.Kayarra:BAAANQADCgEIAgABNQADCgQIBAACAAAAAA==.Kaynarra:BAAANQADCgQIBAAAAA==.Kayonna:BAAANQABCgEIAQABNQADCgQIBAACAAAAAA==.',
Ke='Keastral:BAAANQAECgQIBgAAAA==.Keeynai:BAAANQADCgQIBAAAAA==.Keldanis:BAABNQAECn8iAAIRAAcKHBajbgAyAgARAAcKHBajbgAyAgAAAA==.Kelestrah:BAAANQADCgQJBAAAAA==.Kelterrager:BAAANQADCgMIAwAAAA==.Keony:BAABNQAECn8aAAIdAAcKWRmMVQAWAgAdAAcKWRmMVQAWAgAAAA==.Kerthur:BAAANQADCgYICAAAAA==.',
Ki='Kickpigeons:BAAANQADCgEIAQAAAA==.Killertcells:BAAANQABCgIIAgAAAA==.Kirgrand:BAAANQADCgMIAwAAAA==.Kittyarly:BAAANQAECgYIDAAAAA==.',
Ko='Kodeck:BAAANQADCggIGQAAAA==.Kodokan:BAAANQAECgEIAQAAAA==.Koshima:BAABNQAECn8qAAIaAAkKIBqdNgCZAgAaAAkKIBqdNgCZAgAAAA==.Kozan:BAAANQADCgUICAAAAA==.',
Kr='Krimdan:BAAANQADCgQIBAAAAA==.Krimhit:BAAANQADCgUICwAAAA==.Krimrok:BAAANQABCgIIAgAAAA==.Krimwarr:BAAANQADCgQIBAAAAA==.',
Ku='Kudou:BAAANQADCgMIAwAAAA==.Kudranne:BAAANQADCgQICAABNQAECgQIAgACAAAAAA==.Kugia:BAABNQAECn8mAAIBAAkK1BznDgDiAgABAAkK1BznDgDiAgAAAA==.',
Ky='Kylex:BAAANQAECgEIAQAAAA==.Kynndell:BAAANQADCggIGQAAAA==.Kyo:BAAANQADCgYIDgAAAA==.',
['Kø']='Køkushibø:BAAANQABCgUIBQAAAA==.',
La='Laments:BAAANQADCgUIBQAAAA==.Latak:BAAANQADCgMIAwAAAA==.Latir:BAAANQADCgUIBwAAAA==.Lazylox:BAAANQAECgEIAQAAAA==.Lazyryx:BAAANQADCgUIBQAAAA==.',
Le='Leetheal:BAACNQAFFH8NAAMgAAUKZRegDQD1AAAgAAMKVhOgDQD1AAADAAQKTQSFHQDvAAA1AAQKfykAAwMACQrtFvs+AGsCAAMACQrtFvs+AGsCACAACAr9GoghACcCAAAA.Leethul:BAABNQAECn8mAAIHAAkKyxLySAB1AgAHAAkKyxLySAB1AgAAAA==.Lelethxx:BAAANQAECgIIBAAAAA==.Lesanna:BAABNQAECn8vAAIMAAkKywpXOwDWAQAMAAkKywpXOwDWAQAAAA==.Lestharia:BAAANQAECgUIBQAAAA==.Leysmith:BAABNQAECn8uAAIGAAgKBBOvmgDoAQAGAAgKBBOvmgDoAQAAAA==.',
Li='Lifestream:BAAANQAECgIIAgAAAA==.Lilheal:BAAANQAECgIJAgAAAA==.Lilium:BAAANQADCgYICwAAAA==.Lionël:BAAANQAECgUIBQAAAA==.Lisax:BAAANQADCgIIAgAAAA==.Lizbethe:BAABNQAECn8fAAQTAAgKAiFVBwCPAgATAAcK4CBVBwCPAgAHAAYKBR7BhgDRAQAEAAEKsBjLJwBLAAAAAA==.',
Lo='Loadedtotem:BAAANQAECgMIAwAAAA==.Lockmclovin:BAAANQADCgMIAwAAAA==.Loltank:BAAANQAECgYICgAAAA==.Lomrgreenol:BAAANQADCgQIBAAAAA==.Lopi:BAAANQAECgMIAwAAAA==.Lorast:BAAANQAECgEIAQAAAA==.Lorwater:BAAANQADCgQIBAAAAA==.Loveinfinity:BAAANQABCgIIAgAAAA==.',
Lp='Lp:BAAANQADCgYICAAAAA==.',
Lu='Lumibell:BAAANQABCgYIBwAAAA==.Luminate:BAAANQADCgQIBAAAAA==.Lunaryon:BAAANQADCgUICgAAAA==.',
Ma='Madamgypsy:BAAANQAECgQICAAAAA==.Madderco:BAAANQAECggICAAAAA==.Madivh:BAAANQADCgQIBAAAAA==.Magaspy:BAAANQAECgUIDgAAAA==.Magerage:BAAANQAECgEIAQAAAA==.Magerassfoo:BAAANQAECgUIBgAAAA==.Magiccairne:BAAANQAECgUICgAAAA==.Magikiarly:BAAANQAECgUIBQABNQAECgYIDAACAAAAAA==.Magnar:BAAANQAECgIIAgABNQAECgYIDQACAAAAAA==.Mahoogany:BAAANQADCgYIDAAAAA==.Malson:BAAANQADCgYIBgAAAA==.Mamimage:BAACNQAFFH8LAAIJAAMK6Ba8NADtAAAJAAMK6Ba8NADtAAA1AAQKfzoAAgkACQrGITcbAGkDAAkACQrGITcbAGkDAAAA.Marukka:BAAANQADCgQIBAABNQADCgcIBwACAAAAAA==.Matty:BAAANQADCgEIAQAAAA==.Mayiana:BAAANQAECgMIAwAAAA==.',
Me='Meadowlark:BAAANQAECgQIBAAAAA==.Mefistofeles:BAAANQAECgQICwAAAA==.Mellie:BAAANQADCgQIBQAAAA==.Meowstic:BAABNQAECn8lAAIiAAgKoSLtBgAaAwAiAAgKoSLtBgAaAwABNQAECgIIAgACAAAAAA==.Mercurious:BAAANQAECgQIBwAAAA==.Metalrules:BAAANQABCggICAAAAA==.Methypheni:BAAANQAECgYIDQAAAA==.',
Mi='Mill:BAAANQADCgYICgAAAA==.Minimuff:BAAANQADCgUIBQAAAA==.Mirajanna:BAABNQAECn8uAAIjAAkK9xeVCABnAgAjAAkK9xeVCABnAgAAAA==.Missmouthoff:BAABNQAECn8pAAIDAAgKShdxSgBCAgADAAgKShdxSgBCAgAAAA==.Mitenâ:BAAANQADCgUIBgAAAA==.Mizzxgummy:BAAANQAECgcIBwAAAA==.',
Mo='Momster:BAAANQADCgYIBgAAAA==.Monkin:BAAANQAECgEIAQAAAA==.Moogan:BAAANQAECgQIBgAAAA==.Mookins:BAAANQAECgYIEgAAAA==.Moonfishing:BAABNQAECn8jAAIJAAkKSBZ+dgCQAgAJAAkKSBZ+dgCQAgAAAA==.Moonfly:BAACNQAFFH8MAAIKAAUKyRg5DgCAAQAKAAUKyRg5DgCAAQA1AAQKfyUAAgoACQpRIm0PAEwDAAoACQpRIm0PAEwDAAAA.Morax:BAAANQAECgUIDAAAAA==.Morbidlord:BAAANQABCgYIEQAAAA==.Moscacrazy:BAAANQADCgQIBAAAAA==.Mourne:BAABNQAECn8jAAMOAAkKNxfkHgCFAgAOAAkKNxfkHgCFAgAPAAIKMRHkQwCRAAAAAA==.Mozzan:BAAANQADCgYIBgAAAA==.',
Ms='Mssmalvile:BAAANQADCgYJCwAAAA==.',
Mt='Mtnoflight:BAAANQADCgMIAwAAAA==.',
My='Myrrvain:BAAANQAECgEIAQAAAA==.Mythara:BAAANQADCgYIBgAAAA==.',
Na='Naarcissus:BAAANQABCgIIAgAAAA==.Nagrim:BAAANQAECgEIAQABNQAECgkJHgAeAPwYAA==.Nalaana:BAAANQAECgUIDQAAAA==.Nalariel:BAABNQAECn8gAAMeAAkKoh69KgCJAgAeAAkKoh69KgCJAgAZAAEKgBoAAAAAAAAAAA==.Nallaana:BAAANQADCgUIBQAAAA==.Nalmagedan:BAAANQAECgUIEQAAAA==.Nammi:BAAANQADCgMIAwAAAA==.Nandorr:BAAANQADCgIIAwAAAA==.Nardalem:BAAANQADCgcIBwAAAA==.Narec:BAAANQADCgUIBQAAAA==.Narfhound:BAAANQADCgYICAAAAA==.Nazgrok:BAAANQAECgYIDQAAAA==.',
Ne='Nearhammer:BAAANQAECgEIAQAAAA==.Nearsear:BAAANQADCgcIBwAAAA==.Nefariouz:BAAANQAECggIAQAAAA==.Nervouz:BAABNQAECn8gAAIMAAkKOBNKKwBDAgAMAAkKOBNKKwBDAgAAAA==.Netherpally:BAAANQADCgQJBAAAAA==.',
Ni='Nikis:BAAANQADCgcIDwAAAA==.',
No='Nobbs:BAAANQAECgQIBQAAAA==.Noonecaress:BAAANQAECgIIAgAAAA==.',
Nu='Nualaperafin:BAACNQAFFH8HAAIYAAMK+xSJBAD2AAAYAAMK+xSJBAD2AAA1AAQKfy4AAhgACQpWIIUGABsDABgACQpWIIUGABsDAAAA.',
Ny='Nyvara:BAAANQADCgQIBAABNQAECgQIBwACAAAAAA==.Nyxkitsune:BAAANQADCggIDQAAAA==.',
Od='Odrada:BAAANQADCgQIBAAAAA==.',
Oi='Oiyo:BAAANQABCggICQAAAA==.',
Ok='Okonomiyaki:BAAANQADCgcIBwAAAA==.',
Ol='Olayro:BAABNQAECn8oAAMEAAgK3RI1CAAMAgAEAAgK3RI1CAAMAgAHAAcKrAf+ygAvAQAAAA==.',
Om='Omie:BAAANQADCgcIFwAAAA==.',
On='Onkiea:BAAANQABCgYJBAAAAA==.Onlyrage:BAAANQAECgUJCQAAAA==.',
Oo='Oomkin:BAAANQADCgQIBAAAAA==.Ooptomss:BAABNQAECn8jAAIRAAgKKxJpegAWAgARAAgKKxJpegAWAgAAAA==.',
Op='Openingshift:BAAANQAECgEIAQAAAA==.Ophelìa:BAAANQADCgcIBwAAAA==.Ophilitheda:BAAANQADCgYIAwAAAA==.',
Or='Orclee:BAAANQAECgYIEQAAAA==.',
Pa='Pacificadora:BAAANQAECgQIBgAAAA==.Palaguy:BAAANQADCgQIBAAAAA==.Palkavanka:BAAANQAECgQIEAAAAA==.Pandamonk:BAAANQAECgEIAQAAAA==.',
Pe='Peeonfists:BAAANQADCgEIAQAAAA==.Peeonkeys:BAAANQAECgMIAwAAAA==.Persephie:BAAANQAECgQICwABNQAECgkJHgAeAPwYAA==.Perzeval:BAAANQADCgMJAwAAAA==.',
Ph='Pharmacology:BAABNQAECn8WAAIDAAcKUhq2SwA/AgADAAcKUhq2SwA/AgAAAA==.Phyberlamer:BAAANQADCgEIAQAAAA==.Phénicie:BAAANQADCgYIFgAAAA==.',
Pi='Pinkberri:BAAANQAECgEIAQAAAA==.Pinkblossom:BAAANQAECgQIBQAAAA==.Pipha:BAAANQABCgQIBQAAAA==.Pitchblack:BAAANQADCggIDQAAAA==.',
Pl='Plutochibi:BAAANQABCggICwAAAA==.',
Po='Pocholate:BAAANQADCgcIBwAAAA==.Popa:BAABNQAECn8zAAQdAAkKsBmTLwCmAgAdAAkKsBmTLwCmAgAGAAUKDhk36wA/AQAFAAQKvhSkQQDrAAAAAA==.',
Pr='Prathe:BAAANQAECgYIDwAAAA==.Prayinfury:BAAANQAECgcICAAAAA==.Premorry:BAAANQAECgIIAgAAAA==.Premory:BAAANQADCgUICQAAAA==.Presagee:BAAANQADCgEIAQAAAA==.',
Ps='Psilocy:BAAANQAECgcIDwAAAA==.',
Pu='Pulsate:BAABNQAECn8eAAIkAAgKUxysCgC/AgAkAAgKUxysCgC/AgAAAA==.Purpleduster:BAAANQADCgEIAQAAAA==.',
Py='Pyllo:BAAANQAECggICgAAAA==.',
Qa='Qaucker:BAAANQAECgcIBwAAAA==.',
Qi='Qiz:BAABNQAECn8aAAMIAAcK3xf+HgDvAAAJAAUKqRDvFgFiAQAIAAMKFxz+HgDvAAAAAA==.Qizknows:BAAANQADCgEIAQAAAA==.',
Qu='Quartermain:BAAANQAECggIBwAAAA==.Quistas:BAAANQADCgEIAQAAAA==.',
Qw='Qwish:BAAANQADCgYIBgAAAA==.',
Ra='Rad:BAAANQAECggIDwAAAA==.Radlock:BAAANQAECgMIAQABNQAECggIDwACAAAAAA==.Ragémachine:BAAANQADCgcICwAAAA==.Raijin:BAAANQADCgcICAABNQAECgYIDQACAAAAAA==.Raiken:BAAANQAECgMIBgAAAA==.Raistlen:BAAANQAECgEIAQAAAA==.Rakin:BAAANQABCgQIBAAAAA==.Rakmin:BAAANQAECgQIBQAAAA==.Rarib:BAAANQADCgcIBwAAAA==.Raspberry:BAAANQAECgMIAwAAAA==.Rasto:BAAANQAECgQJBwAAAA==.Raszto:BAAANQADCgIIAgABNQAECgQJBwACAAAAAA==.Rattlebat:BAAANQAECgIIAgAAAA==.',
Re='Redmark:BAAANQAECgQIBAAAAA==.Rendezook:BAAANQAECgQICAAAAA==.Respec:BAAANQADCggICAAAAA==.',
Ri='Rincewind:BAAANQADCggIFQAAAA==.Riohne:BAAANQADCgMIAwAAAA==.Rivexis:BAAANQADCgMIBAAAAA==.',
Ro='Roci:BAAANQADCggIFgAAAA==.Rocker:BAAANQAECggICAAAAA==.Rootway:BAAANQAECgQIBAAAAA==.Roxus:BAABNQAECn8mAAINAAcKwSOJQQDCAgANAAcKwSOJQQDCAgAAAA==.Roxusdruid:BAABNQAECn8VAAIlAAgKewphHgAlAQAlAAgKewphHgAlAQABNQAECggIJgANAMEjAA==.',
Ru='Ruthlin:BAAANQADCgYIBgAAAA==.',
Sa='Sabellal:BAAANQADCgYIBgAAAA==.Saegusa:BAAANQAECgQIDQAAAA==.Saepius:BAAANQAECgIIAgAAAA==.Salestia:BAABNQAECn8hAAIJAAkKtwwWxQD4AQAJAAkKtwwWxQD4AQAAAA==.Samellir:BAAANQAECgMIBAAAAA==.Sanlanesh:BAAANQADCgUIBQAAAA==.Sardothien:BAAANQADCgEIAQAAAA==.Sasive:BAAANQAECgYICgAAAA==.Satanicpanic:BAAANQAECgYICwAAAA==.Sazoku:BAABNQAECn8cAAINAAkK2BxhQQDDAgANAAkK2BxhQQDDAgAAAA==.',
Sc='Scarletlock:BAAANQAECgUIBQABNQAECgkJGwADACceAA==.Scarletnight:BAAANQAECgUIBQABNQAECgkJGwADACceAA==.Schmall:BAAANQAECgYIEgAAAA==.Scrodumpulse:BAAANQADCgcIEAAAAA==.',
Se='Selvalin:BAAANQADCggIDgAAAA==.Sendit:BAAANQAECgcICQAAAA==.Seniormage:BAAANQAECgYIEgAAAA==.Serveil:BAAANQADCgIIAgABNQAFFAIIBQAmACkBAA==.',
Sh='Shaboon:BAAANQAECggICAAAAA==.Shadesprint:BAAANQAECggIBwAAAA==.Shadowhor:BAABNQAECn8dAAIDAAkKIyEuCgBwAwADAAkKIyEuCgBwAwABNQAECgkJLQAHAD4bAA==.Shamamoomoo:BAABNQAECn8fAAIPAAgKKwNQLABbAQAPAAgKKwNQLABbAQAAAA==.Shaninigans:BAAANQADCgEIAQAAAA==.Shaowen:BAAANQADCgYIBgABNQAECgYIDQACAAAAAA==.Shaqeesha:BAAANQADCgUIBQAAAA==.Shenea:BAAANQADCgYICQAAAA==.Shestalker:BAABNQAECn9EAAIRAAkKJRvdLQDiAgARAAkKJRvdLQDiAgAAAA==.Shiau:BAABNQAECn8ZAAISAAgKJAYNPAAwAQASAAgKJAYNPAAwAQAAAA==.Shigaraki:BAAANQAECgQIBAABNQAECgkJMgAbAGkkAA==.Shimura:BAAANQADCgYICQAAAA==.Shinky:BAAANQADCgUIBAABNQAECgkJFwAHALwWAA==.Shý:BAAANQAECgQICwAAAA==.',
Si='Silana:BAAANQADCggIDQAAAA==.Silvaine:BAAANQAECgUICQAAAA==.Silverstorm:BAABNQAECn8YAAINAAgKjBGxmwDSAQANAAgKjBGxmwDSAQAAAA==.Sisterfran:BAAANQAECgEIAQAAAA==.Sixii:BAAANQAECgMIAwAAAA==.',
Sk='Skitzz:BAAANQAECgQICAAAAQ==.',
Sl='Slackr:BAAANQADCgUIBQAAAA==.Slackrm:BAAANQADCgMJBwAAAA==.Slackrp:BAAANQADCgQIBAAAAA==.Slashyr:BAAANQAECgQIDAAAAA==.Slimshadydh:BAAANQAECgQICwAAAA==.',
Sn='Snipez:BAAANQAECgIJAwAAAA==.Snortyhotorc:BAAANQAECgcICwAAAA==.Snortymcgoop:BAABNQAECn8fAAMWAAkKIxghIwAxAgAWAAgKihghIwAxAgARAAEKuRXISAFGAAAAAA==.',
So='Solclipeus:BAABNQAECn83AAIFAAkKaSGxBQBRAwAFAAkKaSGxBQBRAwAAAA==.Soldh:BAAANQAECgUICgABNQAECgkJNwAFAGkhAA==.Sollock:BAAANQAECggIEAABNQAECgkJNwAFAGkhAA==.Solna:BAAANQAECgUIBwABNQAECggIIAADAEQKAA==.Soulrecall:BAAANQAECgIIAwAAAA==.Soupz:BAABNQAECn8YAAIGAAcKWSCHWwCBAgAGAAcKWSCHWwCBAgAAAA==.',
Sp='Sparadin:BAAANQAECgYIEAAAAA==.Spartacûs:BAAANQAECgQJBQABNQAECgcIEAACAAAAAA==.Spikore:BAAANQADCggICgAAAA==.Splitpeaz:BAAANQADCgcJBwAAAA==.',
Sq='Squrìtle:BAAANQAECgQICAAAAA==.',
Sr='Sririacha:BAAANQADCgUIBQABNQAECggIBwACAAAAAA==.',
St='Stabbyjohn:BAAANQADCggICAAAAA==.Stabbypickle:BAAANQAECgYIDQABNQAECgcIHgAdAFwmAA==.Stachelbeere:BAAANQADCgYIBgAAAA==.Steedvegeta:BAAANQAECgQIBAAAAA==.Stickybug:BAAANQAECgQICwAAAA==.Strånge:BAAANQAECgYIBwAAAA==.Stìtch:BAACNQAFFH8VAAIHAAYKmxxmBQAbAgAHAAYKmxxmBQAbAgA1AAQKfzAAAgcACQpXJWwEALADAAcACQpXJWwEALADAAAA.Stítch:BAAANQADCgQIBAABNQAFFAYIFQAHAJscAA==.',
Su='Sukiafaunias:BAAANQAECgEIAgAAAA==.Sukiafloras:BAAANQAECgIIAgAAAA==.Suldån:BAAANQADCggIJwAAAA==.Summondaddy:BAAANQADCgQIBQAAAA==.Sunfurious:BAAANQAECgYIDgAAAA==.Suoop:BAAANQAECgYICwAAAA==.Supan:BAAANQADCgQIBAAAAA==.',
Sw='Swiftshaman:BAAANQAECgEIAQAAAA==.',
Sy='Synvaria:BAAANQAECgUIBQAAAA==.Syraice:BAAANQADCgUIBQABNQAECgkJMwAmAFAaAA==.Syrare:BAAANQAECgMIAgAAAA==.Syvenari:BAAANQAECgMICQAAAA==.',
['Sï']='Sïxx:BAAANQADCgMJAwABNQAECgMIAwACAAAAAA==.',
Ta='Tachisan:BAAANQAECgQICAAAAA==.Taeril:BAAANQADCgQIBAAAAA==.Tamfam:BAAANQADCggJEAAAAA==.Tanburn:BAAANQADCgYICwAAAA==.Tanduinex:BAAANQADCgYIDAAAAA==.Tangal:BAAANQADCggIGAAAAA==.Tankstabber:BAAANQADCgQIBQAAAA==.Tanplate:BAAANQADCgYICAAAAA==.Tarentia:BAAANQABCggIDgAAAA==.Tastytyrande:BAAANQAECgUIBQAAAA==.Tatsumy:BAABNQAECn8fAAIGAAcKKwyH1ABsAQAGAAcKKwyH1ABsAQAAAA==.',
Tc='Tcmon:BAABNQAECn8qAAIRAAkKDByfLgDfAgARAAkKDByfLgDfAgAAAA==.',
Te='Teachings:BAAANQADCgMIAwAAAA==.Teaglizzy:BAAANQADCgEIAQABNQAFFAIIBwAKAGIEAA==.Teehole:BAAANQAECgUICwAAAA==.Telihill:BAAANQADCgUIDgAAAA==.Telsarra:BAAANQAECgQIBgAAAA==.',
Th='Thalenia:BAAANQADCggIGgAAAA==.Thebigtuna:BAABNQAECn8xAAInAAkK8iMQAwCnAwAnAAkK8iMQAwCnAwAAAA==.Thegigatuna:BAAANQADCgMIAwAAAA==.Thekrisaning:BAAANQADCgYIDAAAAA==.Theladydruid:BAABNQAECn8uAAIBAAkKlBR3HABNAgABAAkKlBR3HABNAgAAAA==.Thelnaris:BAAANQADCgEIAQAAAA==.Themeats:BAAANQADCgQIBAAAAA==.Thendezoth:BAAANQAECgEIAgAAAA==.Thighsoffel:BAAANQADCgcIEwAAAA==.Thirdtjme:BAAANQADCgYIBgAAAA==.Thunderhóof:BAAANQABCgYIDQAAAA==.Thôr:BAAANQAECggICAAAAA==.',
Ti='Tigerpa:BAAANQAECgQIDQAAAA==.Tinkernut:BAAANQABCgIIAgAAAA==.Tinypally:BAAANQAECgEIAgAAAA==.Tinyraven:BAABNQAECn8rAAInAAkKZRmxFgCoAgAnAAkKZRmxFgCoAgAAAA==.Tinysmites:BAAANQADCgQIBAAAAA==.Tinystotems:BAAANQAECgQIDAAAAA==.Tinythia:BAAANQADCgUIBQAAAA==.Tioklarus:BAABNQAECn8yAAIkAAcKIQq8HgBkAQAkAAcKIQq8HgBkAQAAAA==.Tisaryn:BAAANQAECgQIBAAAAA==.',
To='Tofulady:BAABNQAECn8pAAIbAAkK3B/1BwAQAwAbAAkK3B/1BwAQAwAAAA==.Tohu:BAAANQAECgYIDgAAAA==.Toshen:BAAANQADCgEIAQAAAA==.Totax:BAAANQAECgEIAQAAAA==.Totemtoker:BAAANQADCggIDQAAAA==.',
Tr='Tremors:BAAANQADCggICAAAAA==.Triggër:BAAANQABCgQIBAABNQAECgEIAQACAAAAAA==.Tromb:BAAANQAECgMIAwAAAA==.',
Tw='Twobithusler:BAAANQAECgIIAgAAAA==.Twoon:BAAANQADCgMIAwAAAA==.Twoone:BAAANQADCgQIBAAAAA==.',
Ty='Tyniarstus:BAAANQADCgYICAAAAA==.',
Ud='Udderfiasco:BAAANQABCgIIAgAAAA==.',
Ug='Uggh:BAAANQADCgUIBQAAAA==.',
Un='Unhowly:BAACNQAFFH8HAAIeAAIKNhsyFgCmAAAeAAIKNhsyFgCmAAA1AAQKfycAAh4ACQp7JRwLAGEDAB4ACQp7JRwLAGEDAAAA.Unpoppable:BAAANQAECgUICQAAAA==.',
Uz='Uzilok:BAAANQAECgYICQAAAA==.',
Va='Vaelyra:BAAANQADCgMIAwABNQAECgkJJgABANQcAA==.Vakir:BAABNQAECn8jAAIZAAkK2BKNPAAOAgAZAAkK2BKNPAAOAgAAAA==.Valmortem:BAEANQADCgcIEgAAAA==.Vapidos:BAAANQAECgQIBwAAAA==.Varynix:BAAANQAECgIIAgABNQAECgYIBwACAAAAAA==.Vatica:BAAANQAECgEIAQAAAA==.',
Ve='Velanoria:BAAANQADCggICwAAAA==.Veldorai:BAAANQADCgYICwAAAA==.Velrenya:BAAANQADCgQIBgAAAA==.Velýndriel:BAAANQAECgUIBAAAAA==.Venvalzhar:BAABNQAECn8mAAMDAAgKCyLAGQAMAwADAAgKCyLAGQAMAwAgAAIKoAKHcQBAAAAAAA==.Veralidaine:BAAANQAECgQIBgAAAA==.Vestammeni:BAABNQAECn8nAAMUAAkKMSCZCADHAgAUAAkKMSCZCADHAgANAAYKCg+zwAB2AQAAAA==.Vexlore:BAAANQADCgYIBwAAAA==.',
Vi='Vixsaurion:BAAANQAECgEIAQAAAA==.',
Vo='Voltx:BAAANQAECgEIAQAAAA==.Vorn:BAAANQADCgcIBwAAAA==.Vow:BAABNQAECn8ZAAIFAAYKwCAzIADgAQAFAAYKwCAzIADgAQAAAA==.',
Vy='Vynlenlor:BAAANQABCgIIAgAAAA==.',
Wc='Wckd:BAAANQAECgYIEgAAAA==.',
We='Weaksnow:BAAANQAECgcIDwABNQAFFAMICwAJAOgWAA==.Weedgoku:BAAANQAECgQIBAAAAA==.Weedvegeta:BAABNQAECn8bAAIJAAkKNhvTQAADAwAJAAkKNhvTQAADAwAAAA==.Wernbirn:BAAANQAECggIAQAAAA==.Wetremin:BAAANQAECgQIBQAAAA==.',
Wh='Whirpy:BAAANQAECgYIEAAAAA==.Whisberis:BAAANQADCgMIAwAAAA==.Whitty:BAAANQADCgQIBAAAAA==.Whizkee:BAAANQAECgcIEgAAAA==.Whookies:BAAANQADCgMIAwABNQAECgYIBgACAAAAAA==.',
Wi='Wildbeefwood:BAAANQAECgUIBQAAAA==.Wingedlady:BAAANQAECgYIDQAAAA==.Wingss:BAABNQAECn8dAAIGAAgKzCEaNwDwAgAGAAgKzCEaNwDwAgAAAA==.',
Wu='Wushu:BAAANQAECgQICgAAAA==.',
Wy='Wyl:BAABNQAECn8bAAIGAAgKmSS9GgBXAwAGAAgKmSS9GgBXAwAAAA==.',
Xe='Xerath:BAAANQAECgUICwAAAA==.',
Xi='Xiing:BAABNQAECn8pAAMUAAkK2xRQEAAhAgAUAAkK2xRQEAAhAgANAAEKAAC0WQEpAAAAAA==.Xinei:BAAANQADCgQIAQAAAA==.Xinhe:BAAANQAECgIIAgAAAA==.',
Xn='Xneutron:BAAANQAECgYIDwAAAA==.',
Xt='Xtravagent:BAAANQADCgIIAgAAAA==.',
Xy='Xyxia:BAAANQADCgcIBwAAAA==.',
Ya='Yaiie:BAABNQAECn8oAAMTAAcK4w3VFgC1AQATAAcKVwzVFgC1AQAEAAYKTA+mDQB7AQAAAA==.',
Yo='Yonna:BAAANQAECgMIAwAAAA==.',
Yu='Yunggrazydk:BAAANQADCgQIBAABNQAECgYIDwACAAAAAA==.Yungholy:BAAANQAECgYIDwAAAA==.Yuuki:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.Yuunggrazy:BAAANQADCgUIBQABNQAECgYIDwACAAAAAA==.',
['Yü']='Yüto:BAABNQAECn8jAAMRAAkKASBPHgAdAwARAAkKASBPHgAdAwAWAAMKrBacVgDHAAAAAA==.',
Za='Zabuto:BAABNQAECn8ZAAIKAAcKqhYgQwDlAQAKAAcKqhYgQwDlAQAAAA==.Zahäära:BAAANQAECgUICQAAAA==.Zaldiz:BAAANQADCgIIAgAAAA==.Zar:BAAANQAECgQIBAAAAA==.Zarathor:BAAANQADCgQIBAABNQAECgYIDQACAAAAAA==.Zarrtan:BAAANQAECgIIAQAAAA==.Zazevo:BAAANQAECgUIDQAAAA==.Zazprie:BAAANQAECgQIDAAAAA==.',
Ze='Zendrozath:BAAANQADCgQIBQABNQAECgQIBgACAAAAAA==.',
Zo='Zooz:BAAANQADCgIIAgAAAA==.',
Zu='Zual:BAAANQAECgIIAgAAAA==.Zularraka:BAAANQAECgUICgAAAA==.',
Zx='Zxeý:BAAANQADCgcIDgAAAA==.',
['Äb']='Äbracadabruh:BAABNQAECn8cAAMJAAcKLhYVugAOAgAJAAcKthQVugAOAgAIAAEKdCJDNgBhAAABNQAECggIDwACAAAAAA==.',
['Äl']='Älissia:BAAANQAECgEIAQAAAA==.',
['Ål']='Ålexthegrëat:BAAANQAECgQIBQABNQAECgkJIQAJALcMAA==.',
['Èm']='Èmandy:BAAANQADCggIDQAAAA==.',
['Ën']='Ëndo:BAABNQAECn8eAAMeAAkK/BjrIQC9AgAeAAkK2hjrIQC9AgAZAAQK6RLyggDsAAAAAA==.',
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
